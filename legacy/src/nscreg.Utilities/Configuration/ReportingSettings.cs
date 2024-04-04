namespace nscreg.Utilities.Configuration
{
    /// <summary>
    /// Settings for reporting system
    /// </summary>
    public class ReportingSettings: ISettings
    {
        public string HostName { get; set; }
        public string ExternalHostName { get; set; }
        public string SecretKey { get; set; }
        public string LinkedServerName { get; set; }
        public string SQLiteConnectionString { get; set; }
    }
}
