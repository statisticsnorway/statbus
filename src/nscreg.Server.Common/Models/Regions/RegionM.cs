using System.ComponentModel.DataAnnotations;

namespace nscreg.Server.Common.Models.Regions
{
    /// <summary>
    ///Region model
    /// </summary>
    public class RegionM
    {
        [Required, DataType(DataType.Text), MinLength(1), MaxLength(75)]
        public string Name { get; set; }

        [Required, DataType(DataType.Text), MinLength(1), MaxLength(14)]
        [RegularExpression("([0-9]*)")]
        public string Code { get; set; }

        [DataType(DataType.Text), MaxLength(75)]
        public string AdminstrativeCenter { get; set; }
    }
}
