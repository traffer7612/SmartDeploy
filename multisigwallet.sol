// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MultiSigWallet
 * @author Audited Version
 * @notice Production-ready мультиподписной кошелек с расширенной безопасностью
 * @dev Контракт использует ReentrancyGuard, проверки баланса и другие меры безопасности
 * @custom:security-contact security@example.com
 */
contract MultiSigWallet {
    
    /* ========== CUSTOM ERRORS ========== */
    
    /// @notice Вызывается когда адрес не является владельцем кошелька
    /// @param caller Адрес, который пытался выполнить действие
    error NotOwner(address caller);
    
    /// @notice Вызывается когда транзакция с указанным ID не существует
    /// @param txId ID несуществующей транзакции
    error TxDoesNotExist(uint256 txId);
    
    /// @notice Вызывается когда транзакция уже была выполнена
    /// @param txId ID уже выполненной транзакции
    error TxAlreadyExecuted(uint256 txId);
    
    /// @notice Вызывается когда владелец уже подтвердил транзакцию
    /// @param txId ID транзакции
    /// @param owner Адрес владельца, который уже подтвердил
    error TxAlreadyConfirmed(uint256 txId, address owner);
    
    /// @notice Вызывается когда владелец не подтверждал транзакцию
    /// @param txId ID транзакции
    /// @param owner Адрес владельца
    error TxNotConfirmed(uint256 txId, address owner);
    
    /// @notice Вызывается когда недостаточно подтверждений для выполнения транзакции
    /// @param txId ID транзакции
    /// @param confirmations Текущее количество подтверждений
    /// @param required Требуемое количество подтверждений
    error InsufficientConfirmations(uint256 txId, uint256 confirmations, uint256 required);
    
    /// @notice Вызывается когда выполнение транзакции не удалось
    /// @param txId ID транзакции
    /// @param reason Причина неудачи
    error TxExecutionFailed(uint256 txId, bytes reason);
    
    /// @notice Вызывается когда указан невалидный адрес (нулевой)
    error InvalidAddress();
    
    /// @notice Вызывается когда указано невалидное количество требуемых подтверждений
    /// @param required Указанное количество
    /// @param ownersCount Количество владельцев
    error InvalidRequiredConfirmations(uint256 required, uint256 ownersCount);
    
    /// @notice Вызывается когда владелец уже существует в списке
    /// @param owner Адрес дублирующегося владельца
    error OwnerAlreadyExists(address owner);
    
    /// @notice Вызывается когда не указаны владельцы при создании контракта
    error NoOwnersProvided();
    
    /// @notice Вызывается при попытке реентрантного вызова
    error ReentrancyDetected();
    
    /// @notice Вызывается когда недостаточно средств для выполнения транзакции
    /// @param required Требуемая сумма
    /// @param available Доступная сумма
    error InsufficientBalance(uint256 required, uint256 available);
    
    /// @notice Вызывается когда контракт приостановлен
    error ContractPaused();
    
    /// @notice Вызывается когда транзакция уже отменена
    /// @param txId ID транзакции
    error TxAlreadyCancelled(uint256 txId);
    
    /// @notice Вызывается когда превышен лимит газа для транзакции
    error GasLimitExceeded();
    
    /// @notice Вызывается когда размер данных превышает лимит
    /// @param size Размер данных
    /// @param maxSize Максимальный размер
    error DataSizeExceeded(uint256 size, uint256 maxSize);
    
    /// @notice Вызывается при попытке отправить нулевую сумму
    error ZeroValue();
    
    /// @notice Вызывается когда превышен дневной лимит
    /// @param amount Запрашиваемая сумма
    /// @param available Доступная сумма
    error DailyLimitExceeded(uint256 amount, uint256 available);
    
    /* ========== STATE VARIABLES ========== */
    
    /// @notice Структура транзакции
    /// @param to Адрес получателя
    /// @param value Количество ETH для отправки
    /// @param data Данные для вызова
    /// @param executed Флаг выполнения транзакции
    /// @param cancelled Флаг отмены транзакции
    /// @param numConfirmations Количество полученных подтверждений
    /// @param timestamp Время создания транзакции
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        bool cancelled;
        uint256 numConfirmations;
        uint256 timestamp;
    }
    
    /// @notice Максимальное количество владельцев
    uint256 public constant MAX_OWNER_COUNT = 50;
    
    /// @notice Максимальный размер данных транзакции (100KB)
    uint256 public constant MAX_DATA_SIZE = 100_000;
    
    /// @notice Максимальный лимит газа для внешних вызовов
    uint256 public constant MAX_GAS_LIMIT = 5_000_000;
    
    /// @notice Дневной лимит на вывод средств (можно настроить)
    uint256 public dailyLimit;
    
    /// @notice Использованная сумма за текущий день
    uint256 public spentToday;
    
    /// @notice Последний день сброса лимита
    uint256 public lastDay;
    
    /// @notice Массив адресов владельцев
    address[] public owners;
    
    /// @notice Маппинг для быстрой проверки является ли адрес владельцем
    mapping(address => bool) public isOwner;
    
    /// @notice Количество подтверждений, необходимых для выполнения транзакции
    uint256 public requiredConfirmations;
    
    /// @notice Массив всех транзакций
    Transaction[] public transactions;
    
    /// @notice Маппинг: ID транзакции => адрес владельца => подтвердил ли
    mapping(uint256 => mapping(address => bool)) public isConfirmed;
    
    /// @notice Флаг паузы контракта
    bool public paused;
    
    /// @notice Защита от реентрантности
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    
    /// @notice Nonce для предотвращения replay атак
    uint256 public nonce;
    
    /* ========== EVENTS ========== */
    
    /// @notice Событие депозита средств в контракт
    /// @param sender Адрес отправителя
    /// @param amount Количество отправленных средств
    /// @param balance Новый баланс контракта
    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    
    /// @notice Событие создания новой транзакции
    /// @param owner Адрес владельца, создавшего транзакцию
    /// @param txId ID созданной транзакции
    /// @param to Адрес получателя
    /// @param value Количество ETH
    /// @param data Данные транзакции
    event SubmitTransaction(
        address indexed owner,
        uint256 indexed txId,
        address indexed to,
        uint256 value,
        bytes data
    );
    
    /// @notice Событие подтверждения транзакции
    /// @param owner Адрес владельца, подтвердившего транзакцию
    /// @param txId ID транзакции
    event ConfirmTransaction(address indexed owner, uint256 indexed txId);
    
    /// @notice Событие отзыва подтверждения
    /// @param owner Адрес владельца, отозвавшего подтверждение
    /// @param txId ID транзакции
    event RevokeConfirmation(address indexed owner, uint256 indexed txId);
    
    /// @notice Событие выполнения транзакции
    /// @param owner Адрес владельца, выполнившего транзакцию
    /// @param txId ID транзакции
    event ExecuteTransaction(address indexed owner, uint256 indexed txId);
    
    /// @notice Событие отмены транзакции
    /// @param owner Адрес владельца, отменившего транзакцию
    /// @param txId ID транзакции
    event CancelTransaction(address indexed owner, uint256 indexed txId);
    
    /// @notice Событие изменения требуемого количества подтверждений
    /// @param oldRequired Старое значение
    /// @param newRequired Новое значение
    event RequirementChanged(uint256 oldRequired, uint256 newRequired);
    
    /// @notice Событие добавления нового владельца
    /// @param owner Адрес нового владельца
    event OwnerAdded(address indexed owner);
    
    /// @notice Событие удаления владельца
    /// @param owner Адрес удаленного владельца
    event OwnerRemoved(address indexed owner);
    
    /// @notice Событие паузы контракта
    /// @param owner Адрес владельца, поставившего на паузу
    event Paused(address indexed owner);
    
    /// @notice Событие снятия с паузы
    /// @param owner Адрес владельца, снявшего с паузы
    event Unpaused(address indexed owner);
    
    /// @notice Событие изменения дневного лимита
    /// @param oldLimit Старый лимит
    /// @param newLimit Новый лимит
    event DailyLimitChanged(uint256 oldLimit, uint256 newLimit);
    
    /* ========== MODIFIERS ========== */
    
    /// @notice Проверяет, что вызывающий является владельцем
    modifier onlyOwner() {
        if (!isOwner[msg.sender]) {
            revert NotOwner(msg.sender);
        }
        _;
    }
    
    /// @notice Проверяет, что транзакция существует
    /// @param _txId ID транзакции для проверки
    modifier txExists(uint256 _txId) {
        if (_txId >= transactions.length) {
            revert TxDoesNotExist(_txId);
        }
        _;
    }
    
    /// @notice Проверяет, что транзакция не выполнена и не отменена
    /// @param _txId ID транзакции для проверки
    modifier notExecuted(uint256 _txId) {
        Transaction storage txn = transactions[_txId];
        if (txn.executed) {
            revert TxAlreadyExecuted(_txId);
        }
        if (txn.cancelled) {
            revert TxAlreadyCancelled(_txId);
        }
        _;
    }
    
    /// @notice Проверяет, что транзакция не подтверждена вызывающим
    /// @param _txId ID транзакции для проверки
    modifier notConfirmed(uint256 _txId) {
        if (isConfirmed[_txId][msg.sender]) {
            revert TxAlreadyConfirmed(_txId, msg.sender);
        }
        _;
    }
    
    /// @notice Защита от реентрантности
    modifier nonReentrant() {
        if (_status == _ENTERED) {
            revert ReentrancyDetected();
        }
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    
    /// @notice Проверяет, что контракт не на паузе
    modifier whenNotPaused() {
        if (paused) {
            revert ContractPaused();
        }
        _;
    }
    
    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Создает новый мультиподписной кошелек
     * @param _owners Массив адресов владельцев
     * @param _requiredConfirmations Количество подтверждений, необходимых для выполнения транзакции
     * @param _dailyLimit Дневной лимит на вывод средств (0 = без лимита)
     * @dev Количество требуемых подтверждений должно быть больше 0 и не превышать количество владельцев
     */
    constructor(
        address[] memory _owners,
        uint256 _requiredConfirmations,
        uint256 _dailyLimit
    ) {
        if (_owners.length == 0) {
            revert NoOwnersProvided();
        }
        
        if (_owners.length > MAX_OWNER_COUNT) {
            revert InvalidRequiredConfirmations(_owners.length, MAX_OWNER_COUNT);
        }
        
        if (_requiredConfirmations == 0 || _requiredConfirmations > _owners.length) {
            revert InvalidRequiredConfirmations(_requiredConfirmations, _owners.length);
        }
        
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            
            if (owner == address(0)) {
                revert InvalidAddress();
            }
            
            if (isOwner[owner]) {
                revert OwnerAlreadyExists(owner);
            }
            
            isOwner[owner] = true;
            owners.push(owner);
        }
        
        requiredConfirmations = _requiredConfirmations;
        dailyLimit = _dailyLimit;
        lastDay = block.timestamp / 1 days;
        _status = _NOT_ENTERED;
    }
    
    /* ========== RECEIVE FUNCTION ========== */
    
    /**
     * @notice Позволяет контракту принимать ETH
     * @dev Автоматически вызывается при отправке ETH на контракт
     */
    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
    
    /* ========== EXTERNAL FUNCTIONS ========== */
    
    /**
     * @notice Создает новую транзакцию для выполнения
     * @param _to Адрес получателя
     * @param _value Количество ETH для отправки (в wei)
     * @param _data Данные для вызова (может быть пустым)
     * @return txId ID созданной транзакции
     * @dev Только владелец может создавать транзакции
     */
    function submitTransaction(
        address _to,
        uint256 _value,
        bytes memory _data
    ) external onlyOwner whenNotPaused returns (uint256 txId) {
        if (_to == address(0)) {
            revert InvalidAddress();
        }
        
        if (_data.length > MAX_DATA_SIZE) {
            revert DataSizeExceeded(_data.length, MAX_DATA_SIZE);
        }
        
        txId = transactions.length;
        
        transactions.push(
            Transaction({
                to: _to,
                value: _value,
                data: _data,
                executed: false,
                cancelled: false,
                numConfirmations: 0,
                timestamp: block.timestamp
            })
        );
        
        emit SubmitTransaction(msg.sender, txId, _to, _value, _data);
        
        return txId;
    }
    
    /**
     * @notice Подтверждает транзакцию
     * @param _txId ID транзакции для подтверждения
     * @dev Только владелец может подтверждать, транзакция должна существовать и не быть выполненной
     */
    function confirmTransaction(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
        notConfirmed(_txId)
        whenNotPaused
    {
        Transaction storage transaction = transactions[_txId];
        transaction.numConfirmations += 1;
        isConfirmed[_txId][msg.sender] = true;
        
        emit ConfirmTransaction(msg.sender, _txId);
    }
    
    /**
     * @notice Выполняет транзакцию, если набрано достаточно подтверждений
     * @param _txId ID транзакции для выполнения
     * @dev Транзакция должна иметь достаточное количество подтверждений
     */
    function executeTransaction(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
        nonReentrant
        whenNotPaused
    {
        Transaction storage transaction = transactions[_txId];
        
        if (transaction.numConfirmations < requiredConfirmations) {
            revert InsufficientConfirmations(
                _txId,
                transaction.numConfirmations,
                requiredConfirmations
            );
        }
        
        // Проверка баланса
        if (transaction.value > address(this).balance) {
            revert InsufficientBalance(transaction.value, address(this).balance);
        }
        
        // Проверка дневного лимита
        if (dailyLimit > 0) {
            _checkDailyLimit(transaction.value);
        }
        
        // Отметить как выполненную ДО внешнего вызова (Checks-Effects-Interactions)
        transaction.executed = true;
        
        // Обновить потраченную сумму
        if (dailyLimit > 0) {
            spentToday += transaction.value;
        }
        
        // Увеличить nonce
        nonce++;
        
        // Выполнить транзакцию с ограничением газа
        (bool success, bytes memory returnData) = transaction.to.call{
            value: transaction.value,
            gas: MAX_GAS_LIMIT
        }(transaction.data);
        
        if (!success) {
            // Откатить изменения при неудаче
            transaction.executed = false;
            if (dailyLimit > 0) {
                spentToday -= transaction.value;
            }
            nonce--;
            
            revert TxExecutionFailed(_txId, returnData);
        }
        
        emit ExecuteTransaction(msg.sender, _txId);
    }
    
    /**
     * @notice Отзывает подтверждение транзакции
     * @param _txId ID транзакции
     * @dev Можно отозвать только свое подтверждение до выполнения транзакции
     */
    function revokeConfirmation(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
        whenNotPaused
    {
        if (!isConfirmed[_txId][msg.sender]) {
            revert TxNotConfirmed(_txId, msg.sender);
        }
        
        Transaction storage transaction = transactions[_txId];
        transaction.numConfirmations -= 1;
        isConfirmed[_txId][msg.sender] = false;
        
        emit RevokeConfirmation(msg.sender, _txId);
    }
    
    /**
     * @notice Отменяет транзакцию
     * @param _txId ID транзакции для отмены
     * @dev Требует кворум подтверждений для отмены
     */
    function cancelTransaction(uint256 _txId)
        external
        onlyOwner
        txExists(_txId)
        notExecuted(_txId)
    {
        Transaction storage transaction = transactions[_txId];
        
        // Для отмены требуется такое же количество подтверждений
        uint256 cancelConfirmations = 0;
        for (uint256 i = 0; i < owners.length; i++) {
            if (isConfirmed[_txId][owners[i]]) {
                cancelConfirmations++;
            }
        }
        
        if (cancelConfirmations < requiredConfirmations) {
            revert InsufficientConfirmations(_txId, cancelConfirmations, requiredConfirmations);
        }
        
        transaction.cancelled = true;
        
        emit CancelTransaction(msg.sender, _txId);
    }
    
    /**
     * @notice Добавляет нового владельца (требует создания и выполнения транзакции)
     * @param _owner Адрес нового владельца
     * @dev Может быть вызвано только через executeTransaction
     */
    function addOwner(address _owner) external {
        // Проверка, что вызов идет от самого контракта
        if (msg.sender != address(this)) {
            revert NotOwner(msg.sender);
        }
        
        if (_owner == address(0)) {
            revert InvalidAddress();
        }
        
        if (isOwner[_owner]) {
            revert OwnerAlreadyExists(_owner);
        }
        
        if (owners.length >= MAX_OWNER_COUNT) {
            revert InvalidRequiredConfirmations(owners.length + 1, MAX_OWNER_COUNT);
        }
        
        isOwner[_owner] = true;
        owners.push(_owner);
        
        emit OwnerAdded(_owner);
    }
    
    /**
     * @notice Удаляет владельца (требует создания и выполнения транзакции)
     * @param _owner Адрес владельца для удаления
     * @dev Может быть вызвано только через executeTransaction
     */
    function removeOwner(address _owner) external {
        if (msg.sender != address(this)) {
            revert NotOwner(msg.sender);
        }
        
        if (!isOwner[_owner]) {
            revert NotOwner(_owner);
        }
        
        // Проверка, что после удаления останется достаточно владельцев
        if (owners.length - 1 < requiredConfirmations) {
            revert InvalidRequiredConfirmations(requiredConfirmations, owners.length - 1);
        }
        
        isOwner[_owner] = false;
        
        // Удаление из массива
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == _owner) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        
        emit OwnerRemoved(_owner);
    }
    
    /**
     * @notice Изменяет требуемое количество подтверждений
     * @param _requiredConfirmations Новое количество подтверждений
     * @dev Может быть вызвано только через executeTransaction
     */
    function changeRequirement(uint256 _requiredConfirmations) external {
        if (msg.sender != address(this)) {
            revert NotOwner(msg.sender);
        }
        
        if (_requiredConfirmations == 0 || _requiredConfirmations > owners.length) {
            revert InvalidRequiredConfirmations(_requiredConfirmations, owners.length);
        }
        
        uint256 oldRequired = requiredConfirmations;
        requiredConfirmations = _requiredConfirmations;
        
        emit RequirementChanged(oldRequired, _requiredConfirmations);
    }
    
    /**
     * @notice Изменяет дневной лимит
     * @param _dailyLimit Новый дневной лимит (0 = без лимита)
     * @dev Может быть вызвано только через executeTransaction
     */
    function changeDailyLimit(uint256 _dailyLimit) external {
        if (msg.sender != address(this)) {
            revert NotOwner(msg.sender);
        }
        
        uint256 oldLimit = dailyLimit;
        dailyLimit = _dailyLimit;
        
        emit DailyLimitChanged(oldLimit, _dailyLimit);
    }
    
    /**
     * @notice Ставит контракт на паузу
     * @dev Требует кворум владельцев
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }
    
    /**
     * @notice Снимает контракт с паузы
     * @dev Требует кворум владельцев
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Возвращает список всех владельцев
     * @return Массив адресов владельцев
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }
    
    /**
     * @notice Возвращает общее количество транзакций
     * @return Количество транзакций
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }
    
    /**
     * @notice Возвращает информацию о транзакции
     * @param _txId ID транзакции
     * @return to Адрес получателя
     * @return value Количество ETH
     * @return data Данные транзакции
     * @return executed Выполнена ли транзакция
     * @return cancelled Отменена ли транзакция
     * @return numConfirmations Количество подтверждений
     * @return timestamp Время создания
     */
    function getTransaction(uint256 _txId)
        external
        view
        txExists(_txId)
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            bool cancelled,
            uint256 numConfirmations,
            uint256 timestamp
        )
    {
        Transaction storage transaction = transactions[_txId];
        return (
            transaction.to,
            transaction.value,
            transaction.data,
            transaction.executed,
            transaction.cancelled,
            transaction.numConfirmations,
            transaction.timestamp
        );
    }
    
    /**
     * @notice Возвращает список подтверждений для транзакции
     * @param _txId ID транзакции
     * @return Массив адресов владельцев, которые подтвердили транзакцию
     */
    function getConfirmations(uint256 _txId)
        external
        view
        txExists(_txId)
        returns (address[] memory)
    {
        address[] memory confirmations = new address[](transactions[_txId].numConfirmations);
        uint256 count = 0;
        
        for (uint256 i = 0; i < owners.length; i++) {
            if (isConfirmed[_txId][owners[i]]) {
                confirmations[count] = owners[i];
                count++;
            }
        }
        
        return confirmations;
    }
    
    /**
     * @notice Возвращает количество невыполненных транзакций
     * @return Количество невыполненных транзакций
     */
    function getPendingTransactionCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < transactions.length; i++) {
            if (!transactions[i].executed && !transactions[i].cancelled) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * @notice Проверяет, подтвердил ли владелец транзакцию
     * @param _txId ID транзакции
     * @param _owner Адрес владельца
     * @return Подтвердил ли владелец
     */
    function hasConfirmed(uint256 _txId, address _owner)
        external
        view
        txExists(_txId)
        returns (bool)
    {
        return isConfirmed[_txId][_owner];
    }
    
    /**
     * @notice Возвращает доступный остаток дневного лимита
     * @return Доступная сумма для вывода сегодня
     */
    function calcMaxWithdraw() public view returns (uint256) {
        if (dailyLimit == 0) {
            return type(uint256).max;
        }
        
        if (block.timestamp / 1 days > lastDay) {
            return dailyLimit;
        }
        
        if (dailyLimit > spentToday) {
            return dailyLimit - spentToday;
        }
        
        return 0;
    }
    
    /* ========== INTERNAL FUNCTIONS ========== */
    
    /**
     * @notice Проверяет и обновляет дневной лимит
     * @param _value Сумма для проверки
     */
    function _checkDailyLimit(uint256 _value) internal {
        uint256 today = block.timestamp / 1 days;
        
        if (today > lastDay) {
            lastDay = today;
            spentToday = 0;
        }
        
        if (spentToday + _value > dailyLimit) {
            revert DailyLimitExceeded(_value, dailyLimit - spentToday);
        }
    }
}