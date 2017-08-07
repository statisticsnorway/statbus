using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.DataSourcesQueue
{
    public class UploadQueueItemVm
    {
        [Required, Range(1, int.MaxValue)]
        public int DataSourceId { get; set; }
        public string Description { get; set; }
    }
}
