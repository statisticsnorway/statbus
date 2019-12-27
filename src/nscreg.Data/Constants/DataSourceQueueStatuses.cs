namespace nscreg.Data.Constants
{
    /// <summary>
    /// Data Source Queue Status Constants
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
