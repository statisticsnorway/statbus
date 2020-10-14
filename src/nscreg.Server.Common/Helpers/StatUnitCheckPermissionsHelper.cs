using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Resources;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Services;

namespace nscreg.Server.Common.Helpers
{
    /// <summary>
    /// Helper class for creating statistical units by rules
    /// </summary>
    public partial class StatUnitCheckPermissionsHelper
    {
        private readonly NSCRegDbContext _dbContext;
        private readonly UserService _userService;
        public StatUnitCheckPermissionsHelper(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
            _userService = new UserService(dbContext);
        }

        public void CheckRegionOrActivityContains(string userId, int? regionId, int? actualRegionId, int? postalRegionId, List<int> activityCategoryList)
        {
            if (_userService.IsInRoleAsync(userId, DefaultRoleNames.Administrator).Result) return;
            var regionIds = new List<int?> { regionId, actualRegionId, postalRegionId }.Where(x => x != null).Select(x => (int)x).ToList();
            CheckRegionOrActivityContains(userId, regionIds, activityCategoryList);
        }
        public void CheckRegionOrActivityContains(string userId, int? regionId, int? actualRegionId, int? postalRegionId, List<int> activityCategoryList, bool isAdmin)
        {
            var regionIds = new List<int?> { regionId, actualRegionId, postalRegionId }.Where(x => x != null).Select(x => (int)x).ToList();
            CheckRegionOrActivityContains(userId, regionIds, activityCategoryList);
        }

        public void CheckRegionOrActivityContains(string userId, List<int> regionIds, List<int> activityCategoryList)
        {
            CheckIfRegionContains(userId, regionIds);
            CheckIfActivityContains(userId, activityCategoryList);
        }

        public bool IsRegionOrActivityContains(string userId, List<int> regionIds, List<int> activityCategoryList)
        {
            try
            {
                CheckRegionOrActivityContains(userId, regionIds, activityCategoryList);
                return true;
            } catch (System.Exception e) when (e is BadRequestException)
            {
                return false;
            }
        }

        public void CheckIfRegionContains(string userId, List<int> regionIds)
        {
            var listRegions = _dbContext.UserRegions.Local
                .Where(au => au.UserId == userId)
                .Select(ur => ur.RegionId)
                .ToList();

            var exceptIds = regionIds.Except(listRegions).ToList();

            if (exceptIds.Any())
            {
                var regionNames = _dbContext.Regions.Local.Where(x => exceptIds.Contains(x.Id))
                    .Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2 }.GetString(CultureInfo.DefaultThreadCurrentCulture)).ToList();
                throw new BadRequestException($"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsRegion))} ({string.Join(",", regionNames.Distinct())})");
            }
        }

        public void CheckIfActivityContains(string userId, List<int> activityCategoryIds)
        {
            var activityCategoryUserIds = _dbContext.ActivityCategoryUsers.Where(au => au.UserId == userId)
                .Select(ur => ur.ActivityCategoryId).ToList();

            var exceptIds = activityCategoryIds.Except(activityCategoryUserIds);

            var activityCategoryNames =
                        _dbContext.ActivityCategories.Local.Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2, Id = x.Id }).Where(x => exceptIds.Contains(x.Id)).Select(x => x.GetString(CultureInfo.DefaultThreadCurrentCulture)).ToList();
            throw new BadRequestException(
                        $"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsActivityCategory))} ({string.Join(',', activityCategoryNames.Distinct())})");
        }
    }
}
