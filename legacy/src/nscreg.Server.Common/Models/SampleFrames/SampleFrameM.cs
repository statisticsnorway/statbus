using System;
using System.Collections.Generic;
using nscreg.Business.SampleFrames;
using nscreg.Data.Entities;
using nscreg.Utilities.Enums.Predicate;
using Newtonsoft.Json;
using nscreg.Data.Constants;

namespace nscreg.Server.Common.Models.SampleFrames
{
    public class SampleFrameM
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public IEnumerable<FieldEnum> Fields { get; set; }
        public ExpressionGroup Predicate { get; set; }
        public DateTimeOffset CreationDate { get; set; }
        public DateTimeOffset? EditingDate { get; set; }
        public SampleFrameGenerationStatuses Status { get; set; }
        public string FilePath { get; set; }
        public DateTimeOffset? GeneratedDateTime { get; set; }


        public static SampleFrameM Create(SampleFrame entity)
        {
            return new SampleFrameM
            {
                Id = entity.Id,
                EditingDate = entity.EditingDate,
                Name = entity.Name,
                Description = entity.Description,
                Predicate = JsonConvert.DeserializeObject<ExpressionGroup>(entity.Predicate),
                Fields = JsonConvert.DeserializeObject<IEnumerable<FieldEnum>>(entity.Fields),
                Status = entity.Status,
                GeneratedDateTime = entity.GeneratedDateTime,
                FilePath = entity.FilePath
            };
        }

        public SampleFrame CreateSampleFrame(string userId)
        {
            return new SampleFrame
            {
                Name = Name,
                Description = Description,
                CreationDate = DateTime.Now,
                EditingDate = DateTime.Now,
                Predicate = JsonConvert.SerializeObject(Predicate),
                Fields = JsonConvert.SerializeObject(Fields),
                Status = SampleFrameGenerationStatuses.Pending,
                GeneratedDateTime = null,
                FilePath = null,
                UserId = userId
            };
        }

        public void UpdateSampleFrame(SampleFrame item, string userId)
        {
            item.Name = Name;
            item.Description = Description;
            item.EditingDate = DateTimeOffset.Now;
            item.CreationDate = item.CreationDate == DateTimeOffset.MinValue ? DateTimeOffset.Now : item.CreationDate;
            item.Predicate = JsonConvert.SerializeObject(Predicate);
            item.Fields = JsonConvert.SerializeObject(Fields);
            item.Status = SampleFrameGenerationStatuses.Pending;
            item.GeneratedDateTime = null;
            item.FilePath = null;
            item.UserId = userId;
        }
    }
}
