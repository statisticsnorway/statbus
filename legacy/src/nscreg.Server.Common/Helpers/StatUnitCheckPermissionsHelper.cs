using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using nscreg.Data;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;

namespace nscreg.Server.Common.Helpers
{
    /// <summary>
    /// Helper class for creating statistical units by rules
    /// </summary>
    public partial class StatUnitCheckPermissionsHelper
    {
        private readonly NSCRegDbContext _dbContext;
        public StatUnitCheckPermissionsHelper(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public void CheckRegionOrActivityContains(string userId, List<int> regionIds, List<int> activityCategoryList, bool isUploadService = false)
        {
            CheckIfRegionContains(userId, regionIds, isUploadService);
            CheckIfActivityContains(userId, activityCategoryList, isUploadService);
        }

        public bool IsRegionOrActivityContains(string userId, List<int> regionIds, List<int> activityCategoryList)
        {
            try
            {
                CheckRegionOrActivityContains(userId, regionIds, activityCategoryList);
                return true;
            }
            catch (BadRequestException)
            {
                return false;
            }
        }

        public void CheckIfRegionContains(string userId, List<int> regionIds, bool isUploadService)
        {
            var listRegions = isUploadService
                ? _dbContext.UserRegions.Local
                    .Where(au => au.UserId == userId)
                    .Select(ur => ur.RegionId)
                    .ToList()
                : _dbContext.UserRegions
                    .Where(au => au.UserId == userId)
                    .Select(ur => ur.RegionId)
                    .ToList();

            var exceptIds = regionIds.Except(listRegions).ToList();

            if (exceptIds.Any())
            {
                var regionNames = _dbContext.Regions.Local.Where(x => exceptIds.Contains(x.Id))
                    .Select(x => new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2 }
                    .GetString(CultureInfo.DefaultThreadCurrentCulture)).ToList();
                throw new BadRequestException($"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsRegion))} ({string.Join(",", regionNames.Distinct())})");
            }
        }

        public void CheckIfActivityContains(string userId, List<int> activityCategoryIds, bool isUploadService)
        {
            var activityCategoryUserIds = _dbContext.ActivityCategoryUsers.Where(au => au.UserId == userId)
                .Select(ur => ur.ActivityCategoryId).ToList();

            var exceptIds = activityCategoryIds.Except(activityCategoryUserIds).ToList();

            if (exceptIds.Any())
            {
                var activityCategoryNames = isUploadService ?
                    _dbContext.ActivityCategories.Local.Select(x =>
                    new CodeLookupBase { Name = x.Name, NameLanguage1 = x.NameLanguage1, NameLanguage2 = x.NameLanguage2, Id = x.Id })
                    .Where(x => exceptIds.Contains(x.Id)).Select(x => x.GetString(CultureInfo.DefaultThreadCurrentCulture))
                    .ToList() : _dbContext
                        .ActivityCategories
                        .Select(x => new CodeLookupBase
                        {
                            Name = x.Name,
                            NameLanguage1 = x.NameLanguage1,
                            NameLanguage2 = x.NameLanguage2,
                            Id = x.Id
                        }).Where(x => exceptIds.Contains(x.Id))
                        .Select(x => x.GetString(CultureInfo.DefaultThreadCurrentCulture)).ToList();
                throw new BadRequestException(
                    $"{Localization.GetString(nameof(Resource.YouDontHaveEnoughtRightsActivityCategory))} ({string.Join(',', activityCategoryNames.Distinct())})");

            }

        }
    }
}
