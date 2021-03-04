using System.ComponentModel.DataAnnotations;

namespace nscreg.Utilities.Configuration
{
    /// <summary>
    /// Class of service settings
    /// </summary>
    public class ServicesSettings: ISettings
    {
        [Required]
        public int StatUnitAnalysisServiceDequeueInterval { get; set; }
        [Required]
        public int DataUploadServiceDequeueInterval { get; set; }
        [Required]
        public int DataUploadServiceCleanupTimeout { get; set; }
        [Required]
        public int SampleFrameGenerationServiceDequeueInterval { get; set; }
        [Required]
        public int SampleFrameGenerationServiceCleanupTimeout { get; set; }
        [Required]
        public string RootPath { get; set; }
        [Required]
        public string UploadDir { get; set; }
        [Required]
        public string SampleFramesDir { get; set; }
        [Required]
        public int DataUploadMaxBufferCount { get; set; }
        [Required]
        public bool PersonGoodQuality { get; set; }
        [Required]
        public int ElementsForRecreateContext { get; set; }
    }
}
