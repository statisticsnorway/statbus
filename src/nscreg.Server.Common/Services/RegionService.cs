using System;
using System.Collections.Generic;
using System.Linq;
using System.Linq.Expressions;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.Regions;
using nscreg.Utilities;

namespace nscreg.Server.Common.Services
{
    /// <summary>
    /// Сервис региона
    /// </summary>
    public class RegionService
    {
        private readonly NSCRegDbContext _context;

        public RegionService(NSCRegDbContext dbContext)
        {
            _context = dbContext;
        }
        /// <summary>
        /// Метод получения списка регионов
        /// </summary>
        /// <param name="model">Модель</param>
        /// <param name="predicate">Предикат</param>
        /// <returns></returns>
        public async Task<SearchVm<Region>> ListAsync(PaginatedQueryM model,
            Expression<Func<Region, bool>> predicate = null)
        {
            IQueryable<Region> query = _context.Regions;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }
            var total = await query.CountAsync();
            var regions = await query.OrderBy(v => v.Code)
                .Skip(Pagination.CalculateSkip(model.PageSize, model.Page, total))
                .Take(model.PageSize)
                .ToListAsync();
            return SearchVm<Region>.Create(regions, total);
        }

        /// <summary>
        /// Метод поиска региона
        /// </summary>
        /// <param name="predicate">Предикат</param>
        /// <param name="limit">Ограничение</param>
        /// <returns></returns>
        public Task<List<Region>> ListAsync(Expression<Func<Region, bool>> predicate = null, int? limit = null)
        {
            IQueryable<Region> query = _context.Regions;
            if (predicate != null)
            {
                query = query.Where(predicate);
            }

            if (limit.HasValue)
            {
                query = query.Take(limit.Value);
            }

            return query.Where(v => !v.IsDeleted).OrderBy(v => v.Code).ToListAsync();
        }

        /// <summary>
        /// Метод получения региона
        /// </summary>
        /// <param name="id">Id</param>
        /// <returns></returns>
        public async Task<Region> GetAsync(int id)
        {
            var region = await _context.Regions.SingleOrDefaultAsync(x => x.Id == id);
            if (region == null) throw new BadRequestException(nameof(Resource.RegionNotExistsError));
            return region;
        }

        /// <summary>
        /// Метод получения списка кодов региона по диапазону
        /// </summary>
        /// <param name="start">Начало</param>
        /// <param name="end">Конец</param>
        /// <returns></returns>
        public async Task<List<Region>> GetByPartCode(string start, string end)
            => await _context.Regions
                .Where(x =>
                    x.Code.StartsWith(start)
                    && x.Code.EndsWith(end))
                .ToListAsync();

        /// <summary>
        /// Метод получения списка адресов
        /// </summary>
        /// <param name="code">Код</param>
        /// <returns></returns>
        public async Task<RegionM> GetAsync(string code)
        {
            var region = await _context.Regions.FirstOrDefaultAsync(x => x.Code.TrimEnd('0').Equals(code));
            return Mapper.Map<RegionM>(region);
        }

        /// <summary>
        /// Метод полечения дерева регионов
        /// </summary>
        /// <returns></returns>
        public async Task<RegionNode> GetRegionTreeAsync()
        {
            const string rootCode = "41700000000000";
            var regions = await _context.Regions.ToListAsync();

            return regions.Where(x => x.Code == rootCode)
                .Select(root => new RegionNode
                {
                    Id = root.Id.ToString(),
                    Name = root.Name,
                    Code = root.Code,
                    RegionNodes = regions
                        .Where(x => x.Code.StartsWith(rootCode.Substring(0, 3)) &&
                                    x.Code.EndsWith(rootCode.Substring(5)) && x.Code != root.Code)
                        .Select(levelOne => new RegionNode
                        {
                            Id = levelOne.Id.ToString(),
                            Name = levelOne.Name,
                            Code = levelOne.Code,
                            RegionNodes =
                                regions.Where(
                                        x => x.Code.StartsWith(levelOne.Code.Substring(0, 5)) &&
                                             x.Code.EndsWith(rootCode.Substring(8)) && x.Code != levelOne.Code)
                                    .Select(levelTwo => new RegionNode
                                    {
                                        Id = levelTwo.Id.ToString(),
                                        Name = levelTwo.Name,
                                        Code = levelTwo.Code,
                                        RegionNodes =
                                            regions.Where(
                                                    x => x.Code.StartsWith(levelTwo.Code.Substring(0, 8)) &&
                                                         x.Code.EndsWith(rootCode.Substring(11)) &&
                                                         x.Code != levelTwo.Code)
                                                .Select(levelThree => new RegionNode
                                                {
                                                    Id = levelThree.Id.ToString(),
                                                    Name = levelThree.Name,
                                                    Code = levelThree.Code,
                                                    RegionNodes =
                                                        regions
                                                            .Where(
                                                                x => x.Code.StartsWith(levelThree.Code
                                                                         .Substring(0, 11)) &&
                                                                     x.Code != levelThree.Code)
                                                            .Select(levelFour => new RegionNode
                                                            {
                                                                Id = levelFour.Id.ToString(),
                                                                Name = levelFour.Name,
                                                                Code = levelFour.Code
                                                            })
                                                            .OrderBy(x => x.Name)
                                                }).OrderBy(x => x.Name)
                                    }).OrderBy(x => x.Name)
                        })
                        .OrderBy(x => x.Name)
                }).Single();
        }

        /// <summary>
        /// Метод создания региона
        /// </summary>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        public async Task<Region> CreateAsync(RegionM data)
        {
            if (await _context.Regions.AnyAsync(x => x.Code == data.Code))
            {
                throw new BadRequestException(nameof(Resource.RegionAlreadyExistsError));
            }
            var region = new Region
            {
                Name = data.Name,
                Code = data.Code,
                AdminstrativeCenter = data.AdminstrativeCenter
            };
            _context.Add(region);
            await _context.SaveChangesAsync();
            return region;
        }

        /// <summary>
        /// Метод редактирования региона
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="data">Данные</param>
        /// <returns></returns>
        public async Task EditAsync(int id, RegionM data)
        {
            if (await _context.Regions.AnyAsync(x => x.Id != id && x.Code == data.Code))
            {
                throw new BadRequestException(nameof(Resource.RegionAlreadyExistsError));
            }
            var region = await GetAsync(id);
            region.Name = data.Name;
            region.Code = data.Code;
            region.AdminstrativeCenter = data.AdminstrativeCenter;
            await _context.SaveChangesAsync();
        }

        /// <summary>
        /// Метод переключения флага удалённости
        /// </summary>
        /// <param name="id">Id</param>
        /// <param name="delete">Флаг удалённости</param>
        /// <returns></returns>
        public async Task DeleteUndelete(int id, bool delete)
        {
            var region = await GetAsync(id);
            region.IsDeleted = delete;
            await _context.SaveChangesAsync();
        }
    }
}
