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
        public IEnumerable<FieldEnum> Fields { get; set; }
        public PredicateExpression Predicate { get; set; }

        public static SampleFrameM Create(SampleFrame entity) =>
            new SampleFrameM
            {
                Id = entity.Id,
                Name = entity.Name,
                Predicate = JsonConvert.DeserializeObject<PredicateExpression>(entity.Predicate),
                Fields = JsonConvert.DeserializeObject<IEnumerable<FieldEnum>>(entity.Fields),
            };

        public SampleFrame CreateSampleFrame(string userId) => new SampleFrame
        {
            Name = Name,
            Predicate = JsonConvert.SerializeObject(Predicate),
            Fields = JsonConvert.SerializeObject(Fields),
            UserId = userId,
        };

        public void UpdateSampleFrame(SampleFrame item, string userId)
        {
            item.Name = Name;
            item.Predicate = JsonConvert.SerializeObject(Predicate);
            item.Fields = JsonConvert.SerializeObject(Fields);
            item.UserId = userId;
        }
    }
}
