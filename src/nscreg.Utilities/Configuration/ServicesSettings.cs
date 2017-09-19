namespace nscreg.Utilities.Configuration
{
    public class ServicesSettings
    {
        public int StatUnitAnalysisServiceDequeueInterval { get; set; }
        public int DataUploadServiceDequeueInterval { get; set; }
        public int DataUploadServiceCleanupTimeout { get; set; }
    }
}
