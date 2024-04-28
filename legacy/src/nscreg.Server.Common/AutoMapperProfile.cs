using System;
using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using nscreg.Data.Entities.ComplexTypes;
using nscreg.Data.Entities.History;
using nscreg.Server.Common.Models.ActivityCategories;
using nscreg.Server.Common.Models.Addresses;
using nscreg.Server.Common.Models.AnalysisQueue;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.Regions;
using nscreg.Server.Common.Models.SampleFrames;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Models.StatUnits.Search;
using nscreg.Server.Common.Services;
using nscreg.Utilities;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common
{
    /// <summary>
    /// Auto-match profile class
    /// </summary>
    public class AutoMapperProfile : Profile
    {
        public AutoMapperProfile()
        {
            DataAccessCondition(CreateStatUnitFromModelMap<LegalUnitCreateM, LegalUnit>()
                .ForMember(x => x.LocalUnits, x => x.Ignore()));
            CreateMap<LegalUnit, LegalUnitCreateM>()
                .ForMember(x => x.LocalUnits, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, opt => opt.MapFrom(src => src.ForeignParticipationCountriesUnits.Select(x => x.Id)));

            DataAccessCondition(CreateStatUnitFromModelMap<LocalUnitCreateM, LocalUnit>());
            CreateStatUnitFromModelReverseMap<LocalUnit, LocalUnitCreateM>();

            DataAccessCondition(CreateStatUnitFromModelMap<EnterpriseUnitCreateM, EnterpriseUnit>()
                .ForMember(x => x.LegalUnits, x => x.Ignore()));
            CreateStatUnitFromModelReverseMap<EnterpriseUnit, EnterpriseUnitCreateM>();

            DataAccessCondition(CreateMap<EnterpriseGroupCreateM, EnterpriseGroup>(MemberList.None)
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))
                .ForMember(x => x.StartPeriod, x => x.MapFrom(v => DateTimeOffset.UtcNow))
                .ForMember(x => x.EndPeriod, x => x.MapFrom(x => DateTime.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.MapFrom(v => DateTimeOffset.UtcNow))
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, x => x.Ignore()));
            CreateMap<EnterpriseGroup, EnterpriseGroupCreateM>(MemberList.None)
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, x => x.Ignore());

            DataAccessCondition(CreateMap<LegalUnitEditM, LegalUnit>()
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.LocalUnits, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, opt => opt.Ignore()));
            CreateMap<LegalUnit, LegalUnitEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.LocalUnits, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, opt => opt.MapFrom(src => src.ForeignParticipationCountriesUnits.Select(x => x.Id)));

            DataAccessCondition(CreateMap<LocalUnitEditM, LocalUnit>()
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, opt => opt.Ignore()));
            CreateMap<LocalUnit, LocalUnitEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x=>x.ForeignParticipationCountriesUnits, opt=>opt.MapFrom(src=>src.ForeignParticipationCountriesUnits.Select(x=>x.Id)));

            DataAccessCondition(CreateMap<EnterpriseUnitEditM, EnterpriseUnit>()
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.LegalUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, opt => opt.Ignore()));
            CreateMap<EnterpriseUnit, EnterpriseUnitEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.LegalUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, opt => opt.MapFrom(src => src.ForeignParticipationCountriesUnits.Select(x => x.Id)));

            DataAccessCondition(CreateMap<EnterpriseGroupEditM, EnterpriseGroup>()
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, x => x.Ignore()));
            CreateMap<EnterpriseGroup, EnterpriseGroupEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, x => x.Ignore());

            CreateMap<Address, AddressM>().ReverseMap();

            CreateMap<ActivityM, Activity>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.UpdatedDate, x => x.MapFrom(v => DateTimeOffset.UtcNow))
                .ForMember(x => x.ActivityCategory, x => x.Ignore());

            CreateMap<Activity, ActivityM>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.IdDate, x => x.MapFrom(v => DateTimeOffset.UtcNow));

            CreateMap<PersonM, Person>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.IdDate, x => x.MapFrom(v => DateTimeOffset.UtcNow));

            CreateMap<Person, PersonM>()
                .ForMember(x => x.Id, x => x.Ignore());

            CreateMap<AddressModel, Address>().ReverseMap();
            CreateMap<RegionM, Region>().ReverseMap();

            CreateMap<CodeLookupVm, UnitLookupVm>();
            CreateMap<DataAccessAttributeM, DataAccessAttributeVm>();
            CreateMap<ActivityCategory, ActivityCategoryVm>();
            CreateMap<SampleFrameM, SampleFrame>().ForMember(x => x.User, x => x.Ignore());

            CreateMap<DataAccessAttributeVm, Permission>()
                .ForMember(x => x.PropertyName, opt => opt.MapFrom(x => x.Name))
                .ForMember(x => x.CanRead, opt => opt.MapFrom(x => x.CanRead))
                .ForMember(x => x.CanWrite, opt => opt.MapFrom(x => x.CanWrite))
                .ForAllMembers(opt=>opt.Ignore());

            CreateMap<AnalysisQueue, AnalysisQueueModel>()
                .ForMember(x => x.UserName, opt => opt.MapFrom(x => x.User.Name));

            CreateMap<ElasticStatUnit, SearchViewAdapterModel>()
                .ForMember(x => x.Address, opt => opt.MapFrom(x => new AddressAdapterModel(
                    new StatUnitSearchView())
                {
                    ActualAddressPart1 = x.ActualAddressPart1 == null ?  x.ActualAddressPart1 : x.ActualAddressPart1 != x.ActualAddressPart1 ? x.ActualAddressPart1 : x.ActualAddressPart1,
                    ActualAddressPart2 = x.ActualAddressPart2 == null ? x.ActualAddressPart2 : x.ActualAddressPart2 != x.ActualAddressPart2 ? x.ActualAddressPart2 : x.ActualAddressPart2
                }))
                .ForMember(x => x.Persons, opt => opt.Ignore())
                .ForMember(x => x.Activities, opt => opt.Ignore());

            CreateMap<StatUnitSearchView, ElasticStatUnit>()
                .ForMember(d => d.RegionIds, opt => opt.MapFrom(s => s.ActualAddressRegionId != null ? new List<int> { (int)s.ActualAddressRegionId } : new List<int>()));

            CreateMap<IStatisticalUnit, ElasticStatUnit>()
                .ForMember(d => d.LiqDate, opt => opt.MapFrom(s => (s is EnterpriseGroup) ? (s as EnterpriseGroup).LiqDateEnd : (s as StatisticalUnit).LiqDate))
                .ForMember(d => d.ActualAddressRegionId, opt => opt.MapFrom(s => s.ActualAddress.RegionId))
                .ForMember(d => d.SectorCodeId, opt => opt.MapFrom(s => s.InstSectorCodeId))
                .ForMember(d => d.ActualAddressPart1, opt => opt.MapFrom(s => s.ActualAddress.AddressPart1))
                .ForMember(d => d.ActualAddressPart2, opt => opt.MapFrom(s => s.ActualAddress.AddressPart2))
                .ForMember(d => d.ActualAddressPart3, opt => opt.MapFrom(s => s.ActualAddress.AddressPart3))
                .ForMember(d => d.ActivityCategoryIds,
                    opt => opt.MapFrom(s =>
                        s.ActivitiesUnits.Select(a => a.Activity.ActivityCategoryId).ToList() ?? new List<int>()
                    )
                )
                .ForMember(d => d.RegionIds,
                    opt => opt.MapFrom(s =>
                        new List<int?> { s.PostalAddress.RegionId, s.ActualAddress.RegionId }
                            .Where(x => x != null).Select(x => (int)x).ToList()
                    )
                );

            ConfigureLookups();
            HistoryMaping();
            CreateStatUnitByRules();
        }

        private IMappingExpression<TStatUnit, CodeLookupVm> CreateStatUnitMap<TStatUnit>()
        where TStatUnit : IStatisticalUnit {
            return CreateMap<TStatUnit, CodeLookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name))
                .ForMember(x => x.Code, opt => opt.MapFrom(x => x.StatId))
                .ForMember(x=>x.NameLanguage1, opt=>opt.Ignore())
                .ForMember(x=>x.NameLanguage2, opt=>opt.Ignore());
        }
        /// <summary>
        /// Метод конфигурации поиска
        /// </summary>
        private void ConfigureLookups()
        {
            CreateStatUnitMap<EnterpriseUnit>();
            CreateStatUnitMap<EnterpriseGroup>();
            CreateStatUnitMap<LocalUnit>();
            CreateStatUnitMap<LegalUnit>();

            CreateMap<Country, CodeLookupVm>();
            CreateMap<SectorCode, CodeLookupVm>();
            CreateMap<LegalForm, CodeLookupVm>();
            CreateMap<DataSourceClassification, CodeLookupVm>();
            CreateMap<ReorgType, CodeLookupVm>();
            CreateMap<UnitSize, CodeLookupVm>();
            CreateMap<ForeignParticipation, CodeLookupVm>();
            CreateMap<UnitStatus, CodeLookupVm>();
            CreateMap<RegistrationReason, CodeLookupVm>();
            CreateMap<PersonType, CodeLookupVm>();
        }

        /// <summary>
        /// Метод сопоставления истории
        /// </summary>
        private void HistoryMaping()
        {
            MapStatisticalUnit<LocalUnit>();

            MapStatisticalUnit<LegalUnit>()
                .ForMember(m => m.LocalUnits, m => m.Ignore());

            MapStatisticalUnit<EnterpriseUnit>()
                .ForMember(m => m.LegalUnits, m => m.Ignore());

            CreateMap<StatisticalUnit, StatisticalUnitHistory>()
                .ForMember(dst=>dst.RegId, opt=>opt.MapFrom(src=>src.RegId));

            CreateMap<StatisticalUnitHistory, StatisticalUnit>()
                .ForMember(dst => dst.RegId, opt => opt.MapFrom(src => src.RegId));

            CreateMap<EnterpriseGroup, EnterpriseGroup>()
                .ForMember(m => m.EnterpriseUnits, m => m.Ignore());

            CreateMap<LocalUnit, LocalUnitHistory>()
                .ForMember(dst => dst.Activities, opt => opt.Ignore())
                .ForMember(dst => dst.Persons, opt => opt.Ignore())
                .ForMember(dst => dst.Countries, opt => opt.Ignore())
                .ForMember(dst => dst.PersonsUnits, opt => opt.MapFrom(src => src.PersonsUnits))
                .ForMember(dst => dst.ActivitiesUnits, opt => opt.MapFrom(src => src.ActivitiesUnits))
                .ForMember(dst => dst.ForeignParticipationCountriesUnits, opt => opt.MapFrom(src => src.ForeignParticipationCountriesUnits));

            CreateMap<LocalUnitHistory, LocalUnit>()
                .ForMember(dst => dst.Activities, opt => opt.Ignore())
                .ForMember(dst => dst.Persons, opt => opt.Ignore())
                .ForMember(dst => dst.PersonsUnits, opt => opt.Ignore())
                .ForMember(dst => dst.ActivitiesUnits, opt => opt.Ignore())
                .ForMember(dst => dst.ForeignParticipationCountriesUnits, opt => opt.Ignore());

            CreateMap<LegalUnit, LegalUnitHistory>()
                .ForMember(dst=>dst.HistoryLocalUnitIds, opt=>opt.MapFrom(src=>src.HistoryLocalUnitIds))
                .ForMember(dst => dst.Activities, opt => opt.Ignore())
                .ForMember(dst => dst.Persons, opt => opt.Ignore())
                .ForMember(dst => dst.Countries, opt => opt.Ignore())
                .ForMember(dst => dst.PersonsUnits, opt => opt.MapFrom(src => src.PersonsUnits))
                .ForMember(dst => dst.ActivitiesUnits, opt => opt.MapFrom(src => src.ActivitiesUnits))
                .ForMember(dst => dst.ForeignParticipationCountriesUnits, opt => opt.MapFrom(src => src.ForeignParticipationCountriesUnits));

            CreateMap<LegalUnitHistory, LegalUnit>()
                .ForMember(dst => dst.HistoryLocalUnitIds, opt => opt.MapFrom(src => src.HistoryLocalUnitIds))
                .ForMember(dst => dst.Activities, opt => opt.Ignore())
                .ForMember(dst => dst.Persons, opt => opt.Ignore())
                .ForMember(dst => dst.PersonsUnits, opt => opt.Ignore())
                .ForMember(dst => dst.ActivitiesUnits, opt => opt.Ignore())
                .ForMember(dst => dst.ForeignParticipationCountriesUnits, opt => opt.Ignore());

            CreateMap<EnterpriseUnit, EnterpriseUnitHistory>()
                .ForMember(dst => dst.Activities, opt => opt.Ignore())
                .ForMember(dst => dst.Persons, opt => opt.Ignore())
                .ForMember(dst => dst.Countries, opt => opt.Ignore())
                .ForMember(dst => dst.PersonsUnits, opt => opt.MapFrom(src => src.PersonsUnits))
                .ForMember(dst => dst.ActivitiesUnits, opt => opt.MapFrom(src => src.ActivitiesUnits))
                .ForMember(dst => dst.ForeignParticipationCountriesUnits, opt => opt.MapFrom(src => src.ForeignParticipationCountriesUnits));
            CreateMap<EnterpriseUnitHistory, EnterpriseUnit>()
                .ForMember(dst => dst.Activities, opt => opt.Ignore())
                .ForMember(dst => dst.Persons, opt => opt.Ignore())
                .ForMember(dst => dst.PersonsUnits, opt => opt.Ignore())
                .ForMember(dst => dst.ActivitiesUnits, opt => opt.Ignore())
                .ForMember(dst => dst.ForeignParticipationCountriesUnits, opt => opt.Ignore());

            CreateMap<EnterpriseGroup, EnterpriseGroupHistory>().ReverseMap();

            CreateMap<ActivityStatisticalUnit, ActivityStatisticalUnitHistory>()
                .ForMember(dst => dst.Unit, opt => opt.Ignore());
            CreateMap<ActivityStatisticalUnitHistory, ActivityStatisticalUnit>()
                .ForMember(dst => dst.Unit, opt => opt.Ignore())
                .ForMember(dst => dst.ActivityId, opt => opt.MapFrom(x => x.Activity.ParentId));
            CreateMap<PersonStatisticalUnit, PersonStatisticalUnitHistory>()
                .ForMember(dst => dst.Unit, opt => opt.Ignore());
            CreateMap<PersonStatisticalUnitHistory, PersonStatisticalUnit>()
                .ForMember(dst => dst.Unit, opt => opt.Ignore());
            CreateMap<CountryStatisticalUnit, CountryStatisticalUnitHistory>()
                .ForMember(dst => dst.Unit, opt => opt.Ignore());
            CreateMap<CountryStatisticalUnitHistory, CountryStatisticalUnit>()
                .ForMember(dst => dst.Unit, opt => opt.Ignore());

            CreateMap<ActivityHistory, Activity>()
                .ForMember(x => x.Id, op => op.MapFrom(x => x.ParentId));

            CreateMap<Activity, ActivityHistory>()
                .ForMember(x => x.Id, op => op.Ignore())
                .ForMember(x => x.ParentId, opt => opt.MapFrom(z => z.Id));
        }

        private void CreateStatUnitByRules()
        {
            CreateMap<LocalUnit, LegalUnit>()
                .ForMember(x => x.MunCapitalShare, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.PrivCapitalShare, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.StateCapitalShare, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.TotalCapital, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.ForeignCapitalShare, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.ForeignCapitalCurrency, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.HistoryLocalUnitIds, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.EntRegIdDate, x => x.MapFrom(x => DateTimeOffset.UtcNow))
                .ForMember(x => x.Market, x => x.MapFrom(x => false))
                .ForMember(x => x.EnterpriseUnitRegId, x => x.MapFrom(x => (int?) null))
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))

                .ForMember(x => x.EnterpriseUnit, x => x.Ignore())
                .ForMember(x => x.RegId, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.ActivitiesUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.PersonsUnits, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, x => x.Ignore())
                .ForMember(x => x.LocalUnits, x => x.Ignore())
                .ForMember(x => x.LegalForm, x => x.Ignore())
                .ForMember(x => x.InstSectorCode, x => x.Ignore());

            CreateMap<LegalUnit, LocalUnit>()
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))
                .ForMember(x => x.LegalUnitIdDate, x => x.MapFrom(x => DateTimeOffset.UtcNow))

                .ForMember(x => x.RegId, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())

                .ForMember(x => x.ActivitiesUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.PersonsUnits, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, x => x.Ignore())
                .ForMember(x => x.LegalForm, x => x.Ignore())
                .ForMember(x => x.LegalUnit, x => x.Ignore())
                .ForMember(x => x.InstSectorCode, x => x.Ignore());

            CreateMap<LegalUnit, EnterpriseUnit>()
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))
                .ForMember(x => x.Commercial, x => x.MapFrom(x => false))
                .ForMember(x => x.EntGroupId, x => x.MapFrom(x => (int?) null))
                .ForMember(x => x.EntGroupIdDate, x => x.Ignore())
                .ForMember(x => x.EntGroupRoleId, x => x.Ignore())
                .ForMember(x => x.HistoryLegalUnitIds, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.EnterpriseGroup, x => x.Ignore())
                .ForMember(x => x.LegalUnits, x => x.Ignore())
                .ForMember(x => x.RegId, x => x.Ignore())
                .ForMember(x => x.ActivitiesUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.PersonsUnits, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, x => x.Ignore())
                .ForMember(x => x.LegalForm, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.InstSectorCode, x => x.Ignore());

            CreateMap<EnterpriseUnit, EnterpriseGroup>()
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))
                .ForMember(x => x.StatusDate, x => x.MapFrom(y => y.StatusDate ?? DateTimeOffset.UtcNow))
                .ForMember(x => x.LiqDateStart, x => x.MapFrom(x => (DateTime?) null))
                .ForMember(x => x.LiqDateEnd, x => x.MapFrom(x => (DateTime?) null))
                .ForMember(x => x.HistoryEnterpriseUnitIds, x => x.MapFrom(x => string.Empty))
                .ForMember(x => x.EntGroupType, x => x.Ignore())
                .ForMember(x => x.RegId, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore());

            CreateMap<AnalisysQueueCreateModel, AnalysisQueue>()
                .ForMember(x => x.UserStartPeriod, opt => opt.MapFrom(x => x.DateFrom))
                .ForMember(x => x.UserEndPeriod, opt => opt.MapFrom(x => x.DateTo))
                .ForMember(x => x.Comment, opt => opt.MapFrom(x => x.Comment));

            CreateMap<Activity, Activity>()
                .ForMember(x => x.ActivityType, opt => opt.PreCondition(x => x.ActivityType != default(ActivityTypes)))
                .ForMember(x => x.ActivityType, opt => opt.MapFrom(x => x.ActivityType))
                .ForMember(x => x.ActivityYear, opt => opt.PreCondition(x => x.ActivityYear != default(int)))
                .ForMember(x => x.ActivityYear, opt => opt.MapFrom(x => x.ActivityYear))
                .ForMember(x => x.Employees, opt => opt.PreCondition(x => x.Employees != default(int)))
                .ForMember(x => x.Employees, opt => opt.MapFrom(x => x.Employees))
                .ForMember(x => x.Turnover, opt => opt.PreCondition(x => x.Turnover != default(decimal?)))
                .ForMember(x => x.Turnover, opt => opt.MapFrom(x => x.Turnover))
                .ForAllMembers(x => x.Ignore());
        }

        /// <summary>
        /// Метод сопоставления стат. единицы
        /// </summary>
        /// <returns></returns>
        private IMappingExpression<T, T> MapStatisticalUnit<T>() where T : StatisticalUnit
            => CreateMap<T, T>()
                .ForMember(v => v.Activities, v => v.Ignore())
                .ForMember(v => v.ActivitiesUnits, v =>
                    v.MapFrom(x => x.ActivitiesUnits.Select(z => new ActivityStatisticalUnit
                    {
                        ActivityId = z.ActivityId,
                        Activity = new Activity
                        {
                            Id = z.Activity.Id,
                            IdDate = z.Activity.IdDate,
                            ActivityCategoryId = z.Activity.ActivityCategoryId,
                            ActivityType = z.Activity.ActivityType,
                            ActivityYear = z.Activity.ActivityYear,
                            Employees = z.Activity.Employees,
                            Turnover = z.Activity.Turnover,
                            UpdatedBy = z.Activity.UpdatedBy,
                            UpdatedByUser = z.Activity.UpdatedByUser,
                            UpdatedDate = z.Activity.UpdatedDate
                        },
                        UnitId = z.UnitId })))
                .ForMember(v => v.Persons, v => v.Ignore())
                .ForMember(v => v.PersonsUnits, v =>
                    v.MapFrom(x => x.PersonsUnits.Select(z => new PersonStatisticalUnit
                    {
                        PersonId = z.PersonId,
                        PersonTypeId = z.PersonTypeId,
                        UnitId = z.UnitId
                    })))
                .ForMember(v => v.ForeignParticipationCountriesUnits, v =>
                    v.MapFrom(x => x.ForeignParticipationCountriesUnits.Select(z => new CountryStatisticalUnit
                    {
                        CountryId = z.CountryId,
                        UnitId = z.UnitId
                    })));

        /// <summary>
        /// Метод создания стат. единицы из модели сопоставления
        /// </summary>
        /// <returns></returns>
        private IMappingExpression<TSource, TDestination> CreateStatUnitFromModelMap<TSource, TDestination>()
            where TSource : StatUnitModelBase
            where TDestination : StatisticalUnit
            => CreateMap<TSource, TDestination>()
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))
                .ForMember(x => x.StartPeriod, x => x.MapFrom(v => DateTimeOffset.UtcNow))
                .ForMember(x => x.EndPeriod, x => x.MapFrom(x => DateTimeOffset.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.MapFrom(v => DateTimeOffset.UtcNow))
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.ActivitiesUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore())
                .ForMember(x => x.ForeignParticipationCountriesUnits, x => x.Ignore());

        /// <summary>
        ///  Метод создания стат. единицы из обратного сопоставления
        /// </summary>
        private void CreateStatUnitFromModelReverseMap<TSource, TDestination>()
            where TSource : StatisticalUnit
            where TDestination : StatUnitModelBase
            => CreateMap<TSource, TDestination>()
                .ForMember(x => x.ChangeReason, x => x.MapFrom(x => ChangeReasons.Create))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.PostalAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore());
        /// <summary>
        /// Метод  обработки условии к доступу данных
        /// </summary>
        private static void DataAccessCondition<TSource, TDestionation>(
            IMappingExpression<TSource, TDestionation> mapping)
            where TSource : IStatUnitM
            where TDestionation : IStatisticalUnit
            =>
                mapping.ForAllMembers(v => v.Condition((src, dst) =>
                {
                    var name = DataAccessAttributesHelper.GetName(dst.GetType(), v.DestinationMember.Name);
                    return DataAccessAttributesProvider.Find(name) == null
                        || (src.DataAccess?.HasWritePermission(name) ?? false);
                }));
    }
}
