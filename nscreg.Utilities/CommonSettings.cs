namespace nscreg.Utilities
{
    public class CommonSettings
    {
        public string ConnectionString { get; set; }
        public bool UseInMemoryDataBase { get; set; }
        public int StatUnitAnalysisServiceDequeueInterval { get; set; }
        public int DataUploadServiceDequeueInterval { get; set; }
        public int DataUploadServiceCleanupTimeout { get; set; }
        public string[] Localizations { get; set; }
        public string DefaultLocalization { get; set; }
    }
}
