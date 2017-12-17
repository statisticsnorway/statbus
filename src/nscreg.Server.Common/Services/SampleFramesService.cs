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

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Sample frame service
    /// </summary>
    public class SampleFramesService
    {
        private readonly NSCRegDbContext _context;
        private readonly UserExpressionTreeParser _userExpressionTreeParser;

        public SampleFramesService(NSCRegDbContext context)
        {
            _context = context;
            _userExpressionTreeParser = new UserExpressionTreeParser();
        }

        /// <summary>
        /// Gets a list of sample frames
        /// </summary>
        /// <param name="model">pagination settings</param>
        /// <returns></returns>
        public async Task<SearchVm<SampleFrameM>> GetAll(PaginatedQueryM model)
        {
            var query = _context.SampleFrames;
            var total = await query.CountAsync();
            return SearchVm<SampleFrameM>.Create(
                (await query
                    .Skip(Pagination.CalculateSkip(model.PageSize, model.Page, total))
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
        public async Task<SampleFrameM> GetById(int id)
        {
            var entity = await _context.SampleFrames.FindAsync(id);
            if (entity == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            return SampleFrameM.Create(entity);
        }

        public async Task<IEnumerable<IReadOnlyDictionary<FieldEnum, string>>> Preview(int id)
        {
            var entity = await _context.SampleFrames.FindAsync(id);
            if (entity == null) throw new NotFoundException(nameof(Resource.SampleFrameNotFound));
            var fields = JsonConvert.DeserializeObject<IEnumerable<FieldEnum>>(entity.Fields)
                .ToDictionary(key => key, key => Enum.GetName(typeof(FieldEnum), key));
            var units = await _context.StatisticalUnits
                .Where(_userExpressionTreeParser.Parse(
                    JsonConvert.DeserializeObject<PredicateExpression>(entity.Predicate)))
                .Take(10)
                .AsNoTracking()
                .ToListAsync();
            return units.Select(unit =>
                fields.ToDictionary(field => field.Key, field => GetPropValue(unit, field.Value)));
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

        private static string GetPropValue(StatisticalUnit unit, string fieldName) =>
            unit.GetType().GetProperty(fieldName)?.GetValue(unit, null)?.ToString() ?? string.Empty;
    }
}
