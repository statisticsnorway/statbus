namespace nscreg.Data.Constants
{
    /// <summary>
    /// Константы статусов очередей источников данных
    /// </summary>
    public enum DataSourceQueueStatuses
    {
        InQueue = 1,
        Loading = 2,
        DataLoadCompleted = 3,
        DataLoadCompletedPartially = 4,
        DataLoadFailed = 5,
    }
}
