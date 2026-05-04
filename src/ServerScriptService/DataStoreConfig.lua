local DataStoreConfig = {
    SaveInStudio = true,
    LoadInStudio = true,
    DebugLogs = true,
    SaveDebounceSeconds = 15,
    ShutdownSaveSpacingSeconds = 0.2,
    ShutdownTimeoutSeconds = 20,
    MaxConcurrentWrites = 2,
    MinimumBudgetThreshold = 1,
    BudgetPollIntervalSeconds = 0.25,
    RetryBackoffSeconds = { 1, 2, 4 },
    SuspiciousSectionThreshold = 2,
}

return DataStoreConfig