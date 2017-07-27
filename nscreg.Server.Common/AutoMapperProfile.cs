using System;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models.ActivityCategories;
using nscreg.Server.Common.Models.Addresses;
using nscreg.Server.Common.Models.DataAccess;
using nscreg.Server.Common.Models.Lookup;
using nscreg.Server.Common.Models.Regions;
using nscreg.Server.Common.Models.StatUnits;
using nscreg.Server.Common.Models.StatUnits.Create;
using nscreg.Server.Common.Models.StatUnits.Edit;
using nscreg.Server.Common.Services;
using nscreg.Utilities;
using nscreg.Utilities.Enums;

namespace nscreg.Server.Common
{
    public class AutoMapperProfile : Profile
    {
        public AutoMapperProfile()
        {
            DataAccessCondition(CreateStatUnitFromModelMap<LegalUnitCreateM, LegalUnit>()
                .ForMember(x => x.LocalUnits, x => x.Ignore()));
            CreateStatUnitFromModelReverseMap<LegalUnit, LegalUnitCreateM>();

            DataAccessCondition(CreateStatUnitFromModelMap<LocalUnitCreateM, LocalUnit>());
            CreateStatUnitFromModelReverseMap<LocalUnit, LocalUnitCreateM>();

            DataAccessCondition(CreateStatUnitFromModelMap<EnterpriseUnitCreateM, EnterpriseUnit>()
                .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                .ForMember(x => x.LocalUnits, opt => opt.Ignore()));
            CreateStatUnitFromModelReverseMap<EnterpriseUnit, EnterpriseUnitCreateM>();

            DataAccessCondition(CreateMap<EnterpriseGroupCreateM, EnterpriseGroup>(MemberList.None)
                .ForMember(x => x.ChangeReason, x => x.UseValue(ChangeReasons.Create))
                .ForMember(x => x.StartPeriod, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.EndPeriod, x => x.UseValue(DateTime.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore()));
            CreateMap<EnterpriseGroup, EnterpriseGroupCreateM>(MemberList.None)
                .ForMember(x => x.ChangeReason, x => x.UseValue(ChangeReasons.Create))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore());

            DataAccessCondition(CreateMap<LegalUnitEditM, LegalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.LocalUnits, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore()));
            CreateMap<LegalUnit, LegalUnitEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.LocalUnits, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore());

            DataAccessCondition(CreateMap<LocalUnitEditM, LocalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore()));
            CreateMap<LocalUnit, LocalUnitEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore());

            DataAccessCondition(CreateMap<EnterpriseUnitEditM, EnterpriseUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.LocalUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore()));
            CreateMap<EnterpriseUnit, EnterpriseUnitEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.LocalUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore());

            DataAccessCondition(CreateMap<EnterpriseGroupEditM, EnterpriseGroup>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore()));
            CreateMap<EnterpriseGroup, EnterpriseGroupEditM>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore());

            CreateMap<Address, AddressM>().ReverseMap();

            CreateMap<ActivityM, Activity>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.UpdatedDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.ActivityRevxCategory, x => x.Ignore());

            CreateMap<PersonM, Person>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.IdDate, x => x.UseValue(DateTime.Now));

            CreateMap<AddressModel, Address>().ReverseMap();
            CreateMap<RegionM, Region>().ReverseMap();

            CreateMap<CodeLookupVm, UnitLookupVm>();
            CreateMap<DataAccessAttributeM, DataAccessAttributeVm>();
            CreateMap<ActivityCategory, ActivityCategoryVm>();

            ConfigureLookups();
            HistoryMaping();
        }

        private void ConfigureLookups()
        {
            CreateMap<EnterpriseUnit, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));

            CreateMap<EnterpriseGroup, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));

            CreateMap<LocalUnit, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));

            CreateMap<LegalUnit, LookupVm>()
                .ForMember(x => x.Id, opt => opt.MapFrom(x => x.RegId))
                .ForMember(x => x.Name, opt => opt.MapFrom(x => x.Name));

            CreateMap<Country, LookupVm>();
        }

        private void HistoryMaping()
        {
            MapStatisticalUnit<LocalUnit>();

            MapStatisticalUnit<LegalUnit>();

            MapStatisticalUnit<EnterpriseUnit>();

            CreateMap<EnterpriseGroup, EnterpriseGroup>();
        }

        private IMappingExpression<T, T> MapStatisticalUnit<T>() where T : StatisticalUnit
            => CreateMap<T, T>()
                //.ForMember(v => v.RegId, v => v.UseValue(0))
                .ForMember(v => v.Activities, v => v.Ignore())
                .ForMember(v => v.ActivitiesUnits, v =>
                    v.MapFrom(x =>
                        x.ActivitiesUnits.Select(z => new ActivityStatisticalUnit() {ActivityId = z.ActivityId})))
                .ForMember(v => v.Persons, v => v.Ignore())
                .ForMember(v => v.PersonsUnits, v =>
                    v.MapFrom(x => x.PersonsUnits.Select(z => new PersonStatisticalUnit {PersonId = z.PersonId})));

        private IMappingExpression<TSource, TDestination> CreateStatUnitFromModelMap<TSource, TDestination>()
            where TSource : StatUnitModelBase
            where TDestination : StatisticalUnit
            => CreateMap<TSource, TDestination>()
                .ForMember(x => x.ChangeReason, x => x.UseValue(ChangeReasons.Create))
                .ForMember(x => x.StartPeriod, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.EndPeriod, x => x.UseValue(DateTime.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.ActivitiesUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore());

        private void CreateStatUnitFromModelReverseMap<TSource, TDestination>()
            where TSource : StatisticalUnit
            where TDestination : StatUnitModelBase
            => CreateMap<TSource, TDestination>()
                .ForMember(x => x.ChangeReason, x => x.UseValue(ChangeReasons.Create))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore())
                .ForMember(x => x.Persons, x => x.Ignore());

        private static void DataAccessCondition<TSource, TDestionation>(
            IMappingExpression<TSource, TDestionation> mapping)
            where TSource : IStatUnitM
            where TDestionation : IStatisticalUnit
            =>
                mapping.ForAllMembers(v => v.Condition((src, dst) =>
                {
                    var name = DataAccessAttributesHelper.GetName(dst.GetType(), v.DestinationMember.Name);
                    return DataAccessAttributesProvider.Find(name) == null
                           || (src.DataAccess?.Contains(name) ?? false);
                }));
    }
}
