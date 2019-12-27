namespace nscreg.Data.Constants
{
    /// <summary>
    /// Data Source Priority Constants
    /// </summary>
    public enum DataSourcePriority
    {
        /// <summary>
        /// Good data quality - no check is required
        /// </summary>
        Trusted = 1,
        /// <summary>
        /// Quality probably acceptable - new units are accepted while updates should be checked manually
        /// </summary>
        Ok = 2,
        /// <summary>
        /// Data quality is bad - all units have to be checked manually
        /// </summary>
        NotTrusted = 3,
    }
}
