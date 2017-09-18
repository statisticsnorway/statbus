using System.Collections.Generic;
using System.Threading.Tasks;
using AutoMapper;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Sample frame service
    /// </summary>
    public class SampleFrameService : ISampleFrameService
    {
        private readonly nscreg.Services.SampleFrames.SampleFrameService _service;

        public SampleFrameService(NSCRegDbContext context)
        {
            _service = new nscreg.Services.SampleFrames.SampleFrameService(context);
        }

        /// <summary>
        /// Creates sample frame
        /// </summary>
        /// <param name="expressionTree"></param>
        /// <param name="data"></param>
        /// <returns></returns>
        public async Task Create(SFExpression expressionTree, SampleFrameM data)
        {
            var sampleFrame = new SampleFrame();
            Mapper.Map(data, sampleFrame);
            await _service.CreateAsync(expressionTree, sampleFrame);
        }

        /// <summary>
        /// Edits sample frame
        /// </summary>
        /// <param name="expressionTree"></param>
        /// <param name="data"></param>
        /// <returns></returns>
        public async Task Edit(SFExpression expressionTree, SampleFrameM data)
        {
            var sampleFrame = new SampleFrame();
            Mapper.Map(data, sampleFrame);
            await _service.EditAsync(expressionTree, sampleFrame);
        }

        /// <summary>
        /// Deletes sample frame
        /// </summary>
        /// <param name="id"></param>
        public void Delete(int id)
        {
            _service.Delete(id);
        }

        public async Task<List<IStatisticalUnit>> View(int id)
        {
            return null;
        }
    }
}
