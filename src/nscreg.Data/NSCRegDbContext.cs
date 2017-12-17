using System.Reflection;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using nscreg.Data.Core;
using nscreg.Data.Entities;

// ReSharper disable UnusedAutoPropertyAccessor.Global
namespace nscreg.Data
{
    /// <summary>
    /// Контекст данных приложения
    /// </summary>
    // ReSharper disable once InconsistentNaming
    public class NSCRegDbContext : IdentityDbContext<User, Role, string>
    {
        public NSCRegDbContext(DbContextOptions options) : base(options)
        {
        }

        /// <summary>
        /// Метод обработчик создания модели
        /// </summary>
        /// <param name="builder"></param>
        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);
            builder.AddEntityTypeConfigurations(GetType().GetTypeInfo().Assembly);
        }

        public DbSet<StatisticalUnit> StatisticalUnits { get; set; }
        public DbSet<LegalUnit> LegalUnits { get; set; }
        public DbSet<EnterpriseUnit> EnterpriseUnits { get; set; }
        public DbSet<LocalUnit> LocalUnits { get; set; }
        public DbSet<EnterpriseGroup> EnterpriseGroups { get; set; }
        public DbSet<Address> Address { get; set; }
        public DbSet<Activity> Activities { get; set; }
        public DbSet<ActivityStatisticalUnit> ActivityStatisticalUnits { get; set; }
        public DbSet<ActivityCategory> ActivityCategories { get; set; }
        public DbSet<ActivityCategoryUser> ActivityCategoryUsers { get; set; }
        public DbSet<Region> Regions { get; set; }
        public DbSet<DataSource> DataSources { get; set; }
        public DbSet<DataSourceQueue> DataSourceQueues { get; set; }
        public DbSet<DataUploadingLog> DataUploadingLogs { get; set; }
        public DbSet<Country> Countries { get; set; }
        public DbSet<LegalForm> LegalForms { get; set; }
        public DbSet<SectorCode> SectorCodes { get; set; }
        public DbSet<Person> Persons { get; set; }
        public DbSet<PersonStatisticalUnit> PersonStatisticalUnits { get; set; }
        public DbSet<UserRegion> UserRegions { get; set; }
        public DbSet<AnalysisLog> AnalysisLogs { get; set; }
        public DbSet<SampleFrame> SampleFrames { get; set; }
        public DbSet<ReorgType> ReorgTypes { get; set; }
        public DbSet<ForeignParticipation> ForeignParticipations { get; set; }
        public DbSet<DataSourceClassification> DataSourceClassifications { get; set; }
        public DbSet<UnitStatus> UnitStatuses { get; set; }
        public DbSet<UnitSize> UnitsSize { get; set; }
        public DbSet<CountryStatisticalUnit> CountryStatisticalUnits { get; set; }
        public DbSet<PostalIndex> PostalIndices { get; set; }
        public DbSet<DictionaryVersion> DictionaryVersions { get; set; }
        public DbSet<AnalysisQueue> AnalysisQueues { get; set; }
        public virtual DbSet<StatUnitSearchView> StatUnitSearchView { get; set; }
    }
}
