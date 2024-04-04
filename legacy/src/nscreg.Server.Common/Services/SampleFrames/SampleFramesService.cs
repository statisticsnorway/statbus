using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using nscreg.Business.SampleFrames;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Utilities;
using nscreg.Utilities.Enums.Predicate;
using Newtonsoft.Json;
using nscreg.Data.Constants;
using System.IO;

namespace nscreg.Server.Common.Services.SampleFrames
{
    /// <summary>
    /// Sample frame service
    /// </summary>
    public class SampleFramesService
    {
        private readonly NSCRegDbContext _context;
        private readonly IConfiguration _configuration;

        public SampleFramesService(NSCRegDbContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }

        /// <summary>
        /// Gets a list of sample frames
        /// </summary>
        /// <param name="model">pagination settings</param>
        /// <returns></returns>
        public async Task<SearchVm<SampleFrameM>> GetAll(SearchQueryM model, string userId)
        {
            var query = _context.SampleFrames
                .Where(x => x.UserId == userId && (string.IsNullOrEmpty(model.Wildcard) || x.Name.ToLower().Contains(model.Wildcard.ToLower())))
                .OrderByDescending(y => y.CreationDate);

            var total = await query.CountAsync<SampleFrame>();
            return SearchVm<SampleFrameM>.Create(
                (await query.Skip<SampleFrame>(Pagination.CalculateSkip(model.PageSize, model.Page, total))
                    .Take(model.PageSize)
                    .AsNoTracking()
                    .ToListAsync())
                .Select(SampleFrameM.Create),
                total);
        }

        /// <summary>
        /// Gets statistical units of sample frame
        /// </summary>
        /// <param name="id"></param>
        /// <returns></returns>
        public async Task<SampleFrameM> GetById(int id, string userId)
        {
            var entity = await _context.SampleFrames.FindAsync(id);
            if (entity == null || entity.UserId != userId) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            return SampleFrameM.Create(entity);
        }

        public async Task<IEnumerable<IReadOnlyDictionary<FieldEnum, string>>> Preview(int id, string userId, int? count = null)
        {
            var sampleFrame = await _context.SampleFrames.FindAsync(id).ConfigureAwait(false);
            if (sampleFrame == null || sampleFrame.UserId != userId) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            var fields = JsonConvert.DeserializeObject<List<FieldEnum>>(sampleFrame.Fields);
            var predicateTree = JsonConvert.DeserializeObject<ExpressionGroup>(sampleFrame.Predicate);

            return await new SampleFrameExecutor(_context, _configuration).Execute(predicateTree, fields, count).ConfigureAwait(false);
        }

        public async Task QueueToDownload(int id, string userId)
        {
            var sampleFrame = await _context.SampleFrames.FindAsync(id);
            if (sampleFrame == null || sampleFrame.UserId != userId) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            sampleFrame.Status = SampleFrameGenerationStatuses.InQueue;
            sampleFrame.FilePath = null;
            sampleFrame.GeneratedDateTime = null;
            await _context.SaveChangesAsync();
        }

        public async Task SetAsDownloaded(int id, string userId)
        {
            var sampleFrame = await _context.SampleFrames.FindAsync(id);
            if (sampleFrame == null || sampleFrame.UserId != userId) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            sampleFrame.Status = SampleFrameGenerationStatuses.Downloaded;
            await _context.SaveChangesAsync();
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
            if (existing == null || existing.UserId != userId) throw new NotFoundException(Resource.SampleFrameNotFound);
            if (File.Exists(existing.FilePath))
                File.Delete(existing.FilePath);
            model.UpdateSampleFrame(existing, userId);
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Deletes sample frame
        /// </summary>
        /// <param name="id"></param>
        public async Task Delete(int id, string userId)
        {
            var existing = await _context.SampleFrames.FindAsync(id);
            if (existing == null || existing.UserId != userId) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            if (File.Exists(existing.FilePath))
                File.Delete(existing.FilePath);
            _context.SampleFrames.Remove(existing);
            await _context.SaveChangesAsync();
        }
    }
}
