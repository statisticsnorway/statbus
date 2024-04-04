using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    /// <summary>
    /// View unit queue load model 
    /// </summary>
    public class UploadQueueItemVm
    {
        [Required, Range(1, int.MaxValue)]
        public int DataSourceId { get; set; }
        public string Description { get; set; }
    }
}
