using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Models.DataSources
{
    public class UploadDataSourceVm
    {
        [Required, Range(1, int.MaxValue)]
        public int DataSourceId { get; set; }
        public string Description { get; set; }
    }
}
