namespace nscreg.Utilities.Configuration
{
    /// <summary>
    /// Class of service settings
    /// </summary>
    public class ServicesSettings
    {
        public int StatUnitAnalysisServiceDequeueInterval { get; set; }
        public int DataUploadServiceDequeueInterval { get; set; }
        public int DataUploadServiceCleanupTimeout { get; set; }
        public int SampleFrameGenerationServiceDequeueInterval { get; set; }
        public int SampleFrameGenerationServiceCleanupTimeout { get; set; }
        public string RootPath { get; set; }
        public string UploadDir { get; set; }
        public string SampleFramesDir { get; set; }
    }
}
