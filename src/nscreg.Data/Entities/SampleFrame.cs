using nscreg.Data.Constants;
using System;

namespace nscreg.Data.Entities
{
    public class SampleFrame
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public string Predicate { get; set; }
        public string Fields { get; set; }
        public string UserId { get; set; }
        public SampleFrameGenerationStatuses Status { get; set; }
        public string FilePath { get; set; }
        public DateTimeOffset? GeneratedDateTime { get; set; }
        public User User { get; set; }
        public DateTimeOffset CreationDate { get; set; }
        public DateTimeOffset? EditingDate { get; set; }
    }
}
