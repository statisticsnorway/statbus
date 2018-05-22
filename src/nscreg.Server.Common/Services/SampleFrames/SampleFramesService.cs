using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Business.SampleFrames;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Utilities;
using nscreg.Utilities.Enums.Predicate;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Services.SampleFrames
{
    /// <summary>
    /// Sample frame service
    /// </summary>
    public class SampleFramesService
    {
        private readonly NSCRegDbContext _context;
        private readonly SampleFrameExecutor _sampleFrameExecutor;

        public SampleFramesService(NSCRegDbContext context)
        {
            _context = context;
            _sampleFrameExecutor = new SampleFrameExecutor(context);
        }

        /// <summary>
        /// Gets a list of sample frames
        /// </summary>
        /// <param name="model">pagination settings</param>
        /// <returns></returns>
        public async Task<SearchVm<SampleFrameM>> GetAll(SearchQueryM model)
        {
            var query = _context.SampleFrames.Where(x => string.IsNullOrEmpty(model.Wildcard) || x.Name.ToLower().Contains(model.Wildcard.ToLower()));

            var total = await query.CountAsync<SampleFrame>();
            return SearchVm<SampleFrameM>.Create(
                (await query.Skip<SampleFrame>(Pagination.CalculateSkip(model.PageSize, model.Page, total))
                    .Take(model.PageSize)
                    .AsNoTracking()
                    .OrderByDescending(x => x.EditingDate)
                    .ToListAsync())
                .Select(SampleFrameM.Create),
                total);
        }

        /// <summary>
        /// Gets statistical units of sample frame
        /// </summary>
        /// <param name="id"></param>
        /// <returns></returns>
        public async Task<SampleFrameM> GetById(int id)
        {
            var entity = await _context.SampleFrames.FindAsync(id);
            if (entity == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            return SampleFrameM.Create(entity);
        }

        public async Task<IEnumerable<IReadOnlyDictionary<FieldEnum, string>>> Preview(int id, int? count = null)
        {
            var sampleFrame = await _context.SampleFrames.FindAsync(id);
            if (sampleFrame == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            var fields = JsonConvert.DeserializeObject<List<FieldEnum>>(sampleFrame.Fields);
            var predicateTree = JsonConvert.DeserializeObject<ExpressionGroup>(sampleFrame.Predicate);

            return await _sampleFrameExecutor.Execute(predicateTree, fields, count);
        }


        /// <summary>
        /// Creates sample frame
        /// </summary>
        /// <param name="model"></param>
        /// <param name="userId"></param>
        /// <returns></returns>
        public async Task<SampleFrameM> Create(SampleFrameM model, string userId)
        {
            var entity = model.CreateSampleFrame(userId);
            _context.SampleFrames.Add(entity);
            await _context.SaveChangesAsync();
            model.Id = entity.Id;
            return model;
        }

        /// <summary>
        /// Edits sample frame
        /// </summary>
        /// <param name="id"></param>
        /// <param name="model"></param>
        /// <param name="userId"></param>
        /// <returns></returns>
        public async Task Edit(int id, SampleFrameM model, string userId)
        {
            var existing = await _context.SampleFrames.FindAsync(id);
            if (existing == null) throw new NotFoundException(Resource.SampleFrameNotFound);
            model.UpdateSampleFrame(existing, userId);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Deletes sample frame
        /// </summary>
        /// <param name="id"></param>
        public async Task Delete(int id)
        {
            var existing = await _context.SampleFrames.FindAsync(id);
            if (existing == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            _context.SampleFrames.Remove(existing);
            await _context.SaveChangesAsync();
        }

    }
}
