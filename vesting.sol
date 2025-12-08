// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title LinearVestingWithCliff
 * @author RemixAI (Improved by Security Audit)
 * @notice Контракт для линейного вестинга ERC20 токенов с периодом cliff
 * @dev Реализует безопасный механизм вестинга с следующими возможностями:
 *      - Период cliff (задержка перед началом разблокировки)
 *      - Cooldown между выводами для защиты от спама
 *      - Минимальная сумма для вывода
 *      - Множественные бенефициары с несколькими вестингами
 *      - Возможность отзыва (revoke) с возвратом невыпущенных токенов
 *      - Пауза для экстренных ситуаций
 *      - Защита от реентрантности
 *      - Оптимизированное хранение данных через mapping
 * 
 * Формула вестинга:
 * - До cliff: 0 токенов доступно
 * - После cliff: линейная разблокировка от start до start + totalDuration
 * - vestedAmount = (totalAmount * elapsedTime) / totalDuration
 * - releasableAmount = vestedAmount - alreadyReleased
 */
contract LinearVestingWithCliff is Ownable, Pausable, ReentrancyGuard {
    constructor() Ownable (msg.sender) {

        }
    using SafeERC20 for IERC20;
    using Strings for uint256;

    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Структура данных о вестинге для одного бенефициара
     * @dev Все временные параметры хранятся в Unix timestamp (секунды)
     * @param beneficiary Адрес получателя токенов
     * @param start Время начала вестинга (Unix timestamp)
     * @param cliffDuration Длительность периода cliff в секундах
     * @param totalDuration Общая длительность вестинга в секундах (включая cliff)
     * @param totalAmount Общее количество токенов для вестинга
     * @param released Количество уже выведенных токенов
     * @param revoked Флаг отзыва вестинга
     * @param revocable Может ли владелец отозвать этот вестинг
     * @param lastClaimTime Время последнего вывода (для cooldown)
     */
    struct VestingSchedule {
        address beneficiary;
        uint256 start;
        uint256 cliffDuration;
        uint256 totalDuration;
        uint256 totalAmount;
        uint256 released;
        bool revoked;
        bool revocable;
        uint256 lastClaimTime;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Токен, используемый для вестинга (неизменяемый)
    IERC20 public immutable token;

    /// @notice Минимальная сумма для вывода (защита от спама микротранзакциями)
    uint256 public minClaimAmount;

    /// @notice Задержка между выводами в секундах (защита от частых транзакций)
    uint256 public claimCooldown;

    /// @notice Флаг инициализации контракта
    bool private initialized;

    /// @notice Счетчик для генерации уникальных ID вестингов
    uint256 private vestingIdCounter;

    /// @notice Маппинг ID вестинга -> данные вестинга
    mapping(uint256 => VestingSchedule) public vestingSchedules;

    /// @notice Маппинг адрес бенефициара -> массив ID его вестингов
    mapping(address => uint256[]) private beneficiaryVestings;

    /// @notice Общее количество токенов, заблокированных в активных вестингах
    uint256 public totalVestedAmount;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Событие инициализации контракта
     * @param tokenAddress Адрес токена для вестинга
     * @param minClaimAmount Минимальная сумма для вывода
     * @param claimCooldown Задержка между выводами
     */
    event Initialized(
        address indexed tokenAddress,
        uint256 minClaimAmount,
        uint256 claimCooldown
    );

    /**
     * @notice Событие создания нового вестинга
     * @param vestingId Уникальный ID вестинга
     * @param beneficiary Адрес бенефициара
     * @param start Время начала
     * @param cliffDuration Длительность cliff
     * @param totalDuration Общая длительность
     * @param totalAmount Общее количество токенов
     * @param revocable Можно ли отозвать
     */
    event VestingCreated(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint256 start,
        uint256 cliffDuration,
        uint256 totalDuration,
        uint256 totalAmount,
        bool revocable
    );

    /**
     * @notice Событие вывода токенов
     * @param vestingId ID вестинга
     * @param beneficiary Адрес бенефициара
     * @param amount Количество выведенных токенов
     */
    event TokensReleased(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint256 amount
    );

    /**
     * @notice Событие отзыва вестинга
     * @param vestingId ID вестинга
     * @param beneficiary Адрес бенефициара
     * @param returnedAmount Количество возвращенных токенов владельцу
     */
    event VestingRevoked(
        uint256 indexed vestingId,
        address indexed beneficiary,
        uint256 returnedAmount
    );

    /**
     * @notice Событие изменения минимальной суммы для вывода
     * @param oldAmount Старое значение
     * @param newAmount Новое значение
     */
    event MinClaimAmountUpdated(uint256 oldAmount, uint256 newAmount);

    /**
     * @notice Событие изменения cooldown периода
     * @param oldCooldown Старое значение
     * @param newCooldown Новое значение
     */
    event ClaimCooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    /**
     * @notice Событие экстренного вывода токенов владельцем
     * @param token Адрес токена
     * @param amount Количество выведенных токенов
     */
    event EmergencyWithdraw(address indexed token, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotInitialized();
    error AlreadyInitialized();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidDuration();
    error InvalidStartTime();
    error InsufficientBalance();
    error InsufficientAllowance();
    error VestingNotFound();
    error NotBeneficiary();
    error CooldownNotEnded(uint256 remainingTime);
    error AmountTooSmall(uint256 amount, uint256 minimum);
    error NotRevocable();
    error AlreadyRevoked();
    error NoTokensToRelease();
    error InvalidVestingId();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Конструктор контракта
     * @dev Устанавливает адрес токена и владельца контракта
     * @param tokenAddress Адрес ERC20 токена для вестинга
     */
     

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Инициализация контракта (вызывается один раз владельцем)
     * @dev Устанавливает параметры для вывода токенов
     * @param minClaimAmount_ Минимальная сумма для вывода (в wei токена)
     * @param claimCooldown_ Задержка между выводами в секундах
     * 
     * Requirements:
     * - Контракт не должен быть инициализирован
     * - Вызывающий должен быть владельцем
     * - Параметры должны быть больше нуля
     * 
     * Emits: {Initialized}
     */
    function initialize(
        uint256 minClaimAmount_,
        uint256 claimCooldown_
    ) external onlyOwner {
        if (initialized) revert AlreadyInitialized();
        if (minClaimAmount_ == 0) revert ZeroAmount();
        if (claimCooldown_ == 0) revert ZeroAmount();

        minClaimAmount = minClaimAmount_;
        claimCooldown = claimCooldown_;
        initialized = true;

        emit Initialized(address(token), minClaimAmount_, claimCooldown_);
    }

    /*//////////////////////////////////////////////////////////////
                        VESTING MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Создание нового графика вестинга
     * @dev Токены переводятся от msg.sender на контракт через transferFrom
     * @param beneficiary_ Адрес получателя токенов
     * @param start_ Время начала вестинга (Unix timestamp)
     * @param cliffDuration_ Длительность cliff в секундах
     * @param totalDuration_ Общая длительность вестинга в секундах
     * @param totalAmount_ Общее количество токенов для вестинга
     * @param revocable_ Может ли владелец отозвать этот вестинг
     * 
     * Requirements:
     * - Контракт должен быть инициализирован
     * - Вызывающий должен быть владельцем
     * - beneficiary_ не должен быть нулевым адресом
     * - start_ должен быть >= текущему времени
     * - cliffDuration_ должен быть < totalDuration_
     * - totalAmount_ должен быть > 0
     * - У msg.sender должен быть достаточный баланс и allowance
     * 
     * Emits: {VestingCreated}
     * 
     * @return vestingId Уникальный ID созданного вестинга
     */
    function createVesting(
        address beneficiary_,
        uint256 start_,
        uint256 cliffDuration_,
        uint256 totalDuration_,
        uint256 totalAmount_,
        bool revocable_
    ) external onlyOwner whenNotPaused returns (uint256 vestingId) {
        if (!initialized) revert NotInitialized();
        if (beneficiary_ == address(0)) revert ZeroAddress();
        if (start_ < block.timestamp) revert InvalidStartTime();
        if (cliffDuration_ >= totalDuration_) revert InvalidDuration();
        if (totalDuration_ == 0) revert InvalidDuration();
        if (totalAmount_ == 0) revert ZeroAmount();

        // Проверяем баланс и allowance отправителя
        if (token.balanceOf(msg.sender) < totalAmount_) {
            revert InsufficientBalance();
        }
        if (token.allowance(msg.sender, address(this)) < totalAmount_) {
            revert InsufficientAllowance();
        }

        // Генерируем уникальный ID
        vestingId = vestingIdCounter++;

        // Создаем новый вестинг
        vestingSchedules[vestingId] = VestingSchedule({
            beneficiary: beneficiary_,
            start: start_,
            cliffDuration: cliffDuration_,
            totalDuration: totalDuration_,
            totalAmount: totalAmount_,
            released: 0,
            revoked: false,
            revocable: revocable_,
            lastClaimTime: 0
        });

        // Добавляем ID в список вестингов бенефициара
        beneficiaryVestings[beneficiary_].push(vestingId);

        // Увеличиваем общую сумму заблокированных токенов
        totalVestedAmount += totalAmount_;

        // Переводим токены на контракт
        token.safeTransferFrom(msg.sender, address(this), totalAmount_);

        emit VestingCreated(
            vestingId,
            beneficiary_,
            start_,
            cliffDuration_,
            totalDuration_,
            totalAmount_,
            revocable_
        );

        return vestingId;
    }

    /**
     * @notice Вывод доступных токенов бенефициаром
     * @dev Проходит по всем вестингам вызывающего и выводит доступные токены
     * 
     * Requirements:
     * - Контракт должен быть инициализирован
     * - Контракт не должен быть на паузе
     * - Должны быть доступные токены для вывода
     * - Сумма должна быть >= minClaimAmount
     * - Должен пройти cooldown период с последнего вывода
     * 
     * Emits: {TokensReleased} для каждого вестинга с выводом
     */
    function release() external nonReentrant whenNotPaused {
        if (!initialized) revert NotInitialized();

        uint256[] memory vestingIds = beneficiaryVestings[msg.sender];
        if (vestingIds.length == 0) revert VestingNotFound();

        uint256 totalReleasable = 0;

        // Проходим по всем вестингам бенефициара
        for (uint256 i = 0; i < vestingIds.length; i++) {
            uint256 vestingId = vestingIds[i];
            VestingSchedule storage schedule = vestingSchedules[vestingId];

            // Пропускаем отозванные вестинги
            if (schedule.revoked) continue;

            // Проверяем cooldown для этого конкретного вестинга
            if (schedule.lastClaimTime > 0) {
                uint256 timeSinceLastClaim = block.timestamp - schedule.lastClaimTime;
                if (timeSinceLastClaim < claimCooldown) {
                    continue; // Пропускаем этот вестинг, но проверяем другие
                }
            }

            uint256 releasable = _computeReleasableAmount(schedule);

            if (releasable > 0) {
                schedule.released += releasable;
                schedule.lastClaimTime = block.timestamp;
                totalReleasable += releasable;

                emit TokensReleased(vestingId, msg.sender, releasable);
            }
        }

        if (totalReleasable == 0) revert NoTokensToRelease();
        if (totalReleasable < minClaimAmount) {
            revert AmountTooSmall(totalReleasable, minClaimAmount);
        }

        // Уменьшаем общую сумму заблокированных токенов
        totalVestedAmount -= totalReleasable;

        // Проверяем баланс контракта перед переводом
        uint256 contractBalance = token.balanceOf(address(this));
        if (contractBalance < totalReleasable) revert InsufficientBalance();

        // Переводим токены бенефициару
        token.safeTransfer(msg.sender, totalReleasable);
    }

    /**
     * @notice Вывод токенов из конкретного вестинга
     * @dev Позволяет бенефициару вывести токены из определенного вестинга
     * @param vestingId ID вестинга для вывода
     * 
     * Requirements:
     * - Контракт должен быть инициализирован
     * - Контракт не должен быть на паузе
     * - Вызывающий должен быть бенефициаром этого вестинга
     * - Вестинг не должен быть отозван
     * - Должен пройти cooldown период
     * - Должны быть доступные токены >= minClaimAmount
     * 
     * Emits: {TokensReleased}
     */
    function releaseFromVesting(uint256 vestingId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (!initialized) revert NotInitialized();

        VestingSchedule storage schedule = vestingSchedules[vestingId];
        
        if (schedule.beneficiary == address(0)) revert InvalidVestingId();
        if (schedule.beneficiary != msg.sender) revert NotBeneficiary();
        if (schedule.revoked) revert AlreadyRevoked();

        // Проверяем cooldown
        if (schedule.lastClaimTime > 0) {
            uint256 timeSinceLastClaim = block.timestamp - schedule.lastClaimTime;
            if (timeSinceLastClaim < claimCooldown) {
                revert CooldownNotEnded(claimCooldown - timeSinceLastClaim);
            }
        }

        uint256 releasable = _computeReleasableAmount(schedule);

        if (releasable == 0) revert NoTokensToRelease();
        if (releasable < minClaimAmount) {
            revert AmountTooSmall(releasable, minClaimAmount);
        }

        schedule.released += releasable;
        schedule.lastClaimTime = block.timestamp;

        // Уменьшаем общую сумму заблокированных токенов
        totalVestedAmount -= releasable;

        // Проверяем баланс контракта
        uint256 contractBalance = token.balanceOf(address(this));
        if (contractBalance < releasable) revert InsufficientBalance();

        // Переводим токены
        token.safeTransfer(msg.sender, releasable);

        emit TokensReleased(vestingId, msg.sender, releasable);
    }

    /**
     * @notice Отзыв вестинга владельцем с возвратом невыпущенных токенов
     * @dev Возвращает владельцу все токены, которые еще не были vested
     * @param vestingId ID вестинга для отзыва
     * 
     * Requirements:
     * - Контракт должен быть инициализирован
     * - Вызывающий должен быть владельцем
     * - Вестинг должен существовать
     * - Вестинг должен быть revocable
     * - Вестинг не должен быть уже отозван
     * 
     * Emits: {VestingRevoked}
     */
    function revokeVesting(uint256 vestingId) external onlyOwner {
        if (!initialized) revert NotInitialized();

        VestingSchedule storage schedule = vestingSchedules[vestingId];

        if (schedule.beneficiary == address(0)) revert InvalidVestingId();
        if (!schedule.revocable) revert NotRevocable();
        if (schedule.revoked) revert AlreadyRevoked();

        // Вычисляем, сколько уже vested (включая уже выведенное)
        uint256 vestedAmount = _computeVestedAmount(schedule);
        
        // Сколько нужно вернуть владельцу
        uint256 returnAmount = schedule.totalAmount - vestedAmount;

        // Помечаем как отозванный
        schedule.revoked = true;

        // Уменьшаем общую сумму заблокированных токенов
        if (returnAmount > 0) {
            totalVestedAmount -= returnAmount;
            
            // Возвращаем токены владельцу
            token.safeTransfer(owner(), returnAmount);
        }

        emit VestingRevoked(vestingId, schedule.beneficiary, returnAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Получить данные инициализации контракта
     * @dev Возвращает основные параметры контракта
     * @return tokenAddress Адрес токена для вестинга
     * @return minClaimAmount_ Минимальная сумма для вывода
     * @return claimCooldown_ Задержка между выводами
     * @return isInitialized Флаг инициализации
     */
    function getInitData()
        external
        view
        returns (
            address tokenAddress,
            uint256 minClaimAmount_,
            uint256 claimCooldown_,
            bool isInitialized
        )
    {
        return (address(token), minClaimAmount, claimCooldown, initialized);
    }

    /**
     * @notice Проверить доступное для вывода количество токенов для адреса
     * @dev Суммирует доступные токены по всем вестингам бенефициара
     * @param beneficiary Адрес бенефициара
     * @return totalReleasable Общее количество доступных для вывода токенов
     */
    function checkReleasableAmount(address beneficiary) 
        external 
        view 
        returns (uint256 totalReleasable) 
    {
        if (!initialized) revert NotInitialized();

        uint256[] memory vestingIds = beneficiaryVestings[beneficiary];

        for (uint256 i = 0; i < vestingIds.length; i++) {
            VestingSchedule storage schedule = vestingSchedules[vestingIds[i]];
            
            if (!schedule.revoked) {
                totalReleasable += _computeReleasableAmount(schedule);
            }
        }

        return totalReleasable;
    }

    /**
     * @notice Проверить доступное количество токенов для конкретного вестинга
     * @param vestingId ID вестинга
     * @return releasable Количество доступных для вывода токенов
     */
    function checkReleasableAmountForVesting(uint256 vestingId)
        external
        view
        returns (uint256 releasable)
    {
        if (!initialized) revert NotInitialized();

        VestingSchedule storage schedule = vestingSchedules[vestingId];
        
        if (schedule.beneficiary == address(0)) revert InvalidVestingId();
        if (schedule.revoked) return 0;

        return _computeReleasableAmount(schedule);
    }

    /**
     * @notice Получить количество активных вестингов для адреса
     * @param beneficiary Адрес бенефициара
     * @return count Количество вестингов (включая отозванные)
     */
    function getVestingCount(address beneficiary) 
        external 
        view 
        returns (uint256 count) 
    {
        return beneficiaryVestings[beneficiary].length;
    }

    /**
     * @notice Получить все ID вестингов для адреса
     * @param beneficiary Адрес бенефициара
     * @return vestingIds Массив ID вестингов
     */
    function getVestingIds(address beneficiary)
        external
        view
        returns (uint256[] memory vestingIds)
    {
        return beneficiaryVestings[beneficiary];
    }

    /**
     * @notice Получить информацию о конкретном вестинге
     * @param vestingId ID вестинга
     * @return schedule Структура с данными вестинга
     */
    function getVestingSchedule(uint256 vestingId)
        external
        view
        returns (VestingSchedule memory schedule)
    {
        if (!initialized) revert NotInitialized();

        schedule = vestingSchedules[vestingId];
        
        if (schedule.beneficiary == address(0)) revert InvalidVestingId();

        return schedule;
    }

    /**
     * @notice Получить детальную информацию о вестинге
     * @param vestingId ID вестинга
     * @return beneficiary Адрес бенефициара
     * @return start Время начала
     * @return cliffEnd Время окончания cliff
     * @return end Время окончания вестинга
     * @return totalAmount Общее количество токенов
     * @return released Уже выведено токенов
     * @return releasable Доступно для вывода сейчас
     * @return vested Всего vested на данный момент
     * @return revocable Можно ли отозвать
     * @return revoked Отозван ли
     */
    function getVestingDetails(uint256 vestingId)
        external
        view
        returns (
            address beneficiary,
            uint256 start,
            uint256 cliffEnd,
            uint256 end,
            uint256 totalAmount,
            uint256 released,
            uint256 releasable,
            uint256 vested,
            bool revocable,
            bool revoked
        )
    {
        if (!initialized) revert NotInitialized();

        VestingSchedule storage schedule = vestingSchedules[vestingId];
        
        if (schedule.beneficiary == address(0)) revert InvalidVestingId();

        beneficiary = schedule.beneficiary;
        start = schedule.start;
        cliffEnd = schedule.start + schedule.cliffDuration;
        end = schedule.start + schedule.totalDuration;
        totalAmount = schedule.totalAmount;
        released = schedule.released;
        releasable = schedule.revoked ? 0 : _computeReleasableAmount(schedule);
        vested = schedule.revoked ? released : _computeVestedAmount(schedule);
        revocable = schedule.revocable;
        revoked = schedule.revoked;
    }

    /**
     * @notice Проверить, можно ли сейчас вывести токены из вестинга
     * @param vestingId ID вестинга
     * @return canClaim Можно ли вывести
     * @return reason Причина, если нельзя
     */
    function canClaimFromVesting(uint256 vestingId)
        external
        view
        returns (bool canClaim, string memory reason)
    {
        if (!initialized) {
            return (false, "Contract not initialized");
        }

        VestingSchedule storage schedule = vestingSchedules[vestingId];

        if (schedule.beneficiary == address(0)) {
            return (false, "Invalid vesting ID");
        }

        if (schedule.revoked) {
            return (false, "Vesting revoked");
        }

        if (schedule.lastClaimTime > 0) {
            uint256 timeSinceLastClaim = block.timestamp - schedule.lastClaimTime;
            if (timeSinceLastClaim < claimCooldown) {
                return (
                    false,
                    string.concat(
                        "Cooldown not ended. Wait ",
                        (claimCooldown - timeSinceLastClaim).toString(),
                        " seconds"
                    )
                );
            }
        }

        uint256 releasable = _computeReleasableAmount(schedule);

        if (releasable == 0) {
            return (false, "No tokens to release");
        }

        if (releasable < minClaimAmount) {
            return (
                false,
                string.concat(
                    "Amount too small. Need at least ",
                    minClaimAmount.toString()
                )
            );
        }

        return (true, "Can claim");
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Вычисляет количество vested токенов на текущий момент
     * @dev Использует линейную формулу: vestedAmount = (totalAmount * elapsed) / totalDuration
     * @param schedule График вестинга
     * @return vestedAmount Количество vested токенов (включая уже выведенные)
     */
    function _computeVestedAmount(VestingSchedule storage schedule)
        internal
        view
        returns (uint256 vestedAmount)
    {
        uint256 currentTime = block.timestamp;

        // До начала вестинга
        if (currentTime < schedule.start) {
            return 0;
        }

        // В период cliff - ничего не vested
        if (currentTime < schedule.start + schedule.cliffDuration) {
            return 0;
        }

        uint256 elapsed = currentTime - schedule.start;

        // После завершения вестинга - все токены vested
        if (elapsed >= schedule.totalDuration) {
            return schedule.totalAmount;
        }

        // Линейный vesting: vestedAmount = (totalAmount * elapsed) / totalDuration
        vestedAmount = (schedule.totalAmount * elapsed) / schedule.totalDuration;

        return vestedAmount;
    }

    /**
     * @notice Вычисляет доступное для вывода количество токенов
     * @dev releasableAmount = vestedAmount - alreadyReleased
     * @param schedule График вестинга
     * @return Доступное для вывода количество токенов
     */
    function _computeReleasableAmount(VestingSchedule storage schedule)
        internal
        view
        returns (uint256)
    {
        uint256 vestedAmount = _computeVestedAmount(schedule);
        return vestedAmount - schedule.released;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Обновить минимальную сумму для вывода
     * @dev Может вызвать только владелец
     * @param newMinClaimAmount Новое значение минимальной суммы
     * 
     * Requirements:
     * - Вызывающий должен быть владельцем
     * - Новое значение должно быть > 0
     * 
     * Emits: {MinClaimAmountUpdated}
     */
    function updateMinClaimAmount(uint256 newMinClaimAmount) external onlyOwner {
        if (newMinClaimAmount == 0) revert ZeroAmount();

        uint256 oldAmount = minClaimAmount;
        minClaimAmount = newMinClaimAmount;

        emit MinClaimAmountUpdated(oldAmount, newMinClaimAmount);
    }

    /**
     * @notice Обновить cooldown период
     * @dev Может вызвать только владелец
     * @param newClaimCooldown Новое значение cooldown в секундах
     * 
     * Requirements:
     * - Вызывающий должен быть владельцем
     * - Новое значение должно быть > 0
     * 
     * Emits: {ClaimCooldownUpdated}
     */
    function updateClaimCooldown(uint256 newClaimCooldown) external onlyOwner {
        if (newClaimCooldown == 0) revert ZeroAmount();

        uint256 oldCooldown = claimCooldown;
        claimCooldown = newClaimCooldown;

        emit ClaimCooldownUpdated(oldCooldown, newClaimCooldown);
    }

    /**
     * @notice Поставить контракт на паузу
     * @dev Останавливает все операции вывода и создания вестингов
     * 
     * Requirements:
     * - Вызывающий должен быть владельцем
     * - Контракт не должен быть на паузе
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Снять контракт с паузы
     * @dev Возобновляет все операции
     * 
     * Requirements:
     * - Вызывающий должен быть владельцем
     * - Контракт должен быть на паузе
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Экстренный вывод токенов владельцем
     * @dev ВНИМАНИЕ: Использовать только в критических ситуациях!
     *      Выводит только "свободные" токены (не заблокированные в вестингах)
     * @param amount Количество токенов для вывода
     * 
     * Requirements:
     * - Вызывающий должен быть владельцем
     * - Контракт должен быть на паузе
     * - amount не должен превышать свободные токены
     * 
     * Emits: {EmergencyWithdraw}
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner whenPaused {
        if (amount == 0) revert ZeroAmount();

        uint256 contractBalance = token.balanceOf(address(this));
        uint256 freeBalance = contractBalance - totalVestedAmount;

        if (amount > freeBalance) revert InsufficientBalance();

        token.safeTransfer(owner(), amount);

        emit EmergencyWithdraw(address(token), amount);
    }

    /**
     * @notice Получить количество свободных (не заблокированных) токенов
     * @dev Свободные токены = баланс контракта - заблокированные в вестингах
     * @return freeBalance Количество свободных токенов
     */
    function getFreeBalance() external view returns (uint256 freeBalance) {
        uint256 contractBalance = token.balanceOf(address(this));
        return contractBalance > totalVestedAmount 
            ? contractBalance - totalVestedAmount 
            : 0;
    }
}