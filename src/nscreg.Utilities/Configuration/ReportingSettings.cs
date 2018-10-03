namespace nscreg.Utilities.Configuration
{
    /// <summary>
    /// Settings for reporting system
    /// </summary>
    public class ReportingSettings
    {
        public string HostName { get; set; }
        public string ExternalHostName { get; set; }
        public string SecretKey { get; set; }
        public string LinkedServerName { get; set; }
        public string ConnectionString { get; set; }
    }
}
