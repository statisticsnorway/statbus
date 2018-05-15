using System.Collections.Generic;
using nscreg.Business.SampleFrames;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Models.SampleFrames
{
    public class SampleFrameM
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public IEnumerable<FieldEnum> Fields { get; set; }
        public ExpressionGroup Predicate { get; set; }

        public static SampleFrameM Create(SampleFrame entity)
        {
            return new SampleFrameM
            {
                Id = entity.Id,
                Name = entity.Name,
                Description = entity.Description,
                Predicate = JsonConvert.DeserializeObject<ExpressionGroup>(entity.Predicate),
                Fields = JsonConvert.DeserializeObject<IEnumerable<FieldEnum>>(entity.Fields)
            };
        }

        public SampleFrame CreateSampleFrame(string userId)
        {
            return new SampleFrame
            {
                Name = Name,
                Description = Description,
                Predicate = JsonConvert.SerializeObject(Predicate),
                Fields = JsonConvert.SerializeObject(Fields),
                UserId = userId
            };
        }

        public void UpdateSampleFrame(SampleFrame item, string userId)
        {
            item.Name = Name;
            item.Description = Description;
            item.Predicate = JsonConvert.SerializeObject(Predicate);
            item.Fields = JsonConvert.SerializeObject(Fields);
            item.UserId = userId;
        }
    }
}
