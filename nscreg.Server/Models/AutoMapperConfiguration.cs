using System;
using System.Collections.Generic;
using System.Linq;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Server.Models.Lookup;
using nscreg.Server.Models.StatUnits;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;

namespace nscreg.Server.Models
{
    public static class AutoMapperConfiguration
    {
        public static void Configure()
        {
            Mapper.Initialize(x => { x.AddProfile<AutoMapperProfile>(); });
        }
    }

    internal class AutoMapperProfile : Profile
    {
        public AutoMapperProfile()
        {
            CreateMap<StatUnitModelBase, StatisticalUnit>()
                .ForMember(x => x.StartPeriod, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.EndPeriod, x => x.UseValue(DateTime.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.ActivitiesUnits, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore());
//                .Include<LegalUnitCreateM, LegalUnit>()
//                .Include<LocalUnitCreateM, LocalUnit>();

            CreateMap<LegalUnitCreateM, LegalUnit>();

            CreateMap<LocalUnitCreateM, LocalUnit>();

            CreateMap<EnterpriseUnitCreateM, EnterpriseUnit>()
                .IncludeBase<StatUnitModelBase, StatisticalUnit>()
                .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                .ForMember(x => x.LocalUnits, opt => opt.Ignore());

            CreateMap<EnterpriseGroupCreateM, EnterpriseGroup>(MemberList.None)
                .ForMember(x => x.StartPeriod, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.EndPeriod, x => x.UseValue(DateTime.MaxValue))
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore());

            CreateMap<LegalUnitEditM, LegalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore());
            CreateMap<LocalUnitEditM, LocalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore());
            CreateMap<EnterpriseUnitEditM, EnterpriseUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.LocalUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore())
                .ForMember(x => x.Activities, x => x.Ignore());
            CreateMap<EnterpriseGroupEditM, EnterpriseGroup>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore())
                .ForMember(x => x.EnterpriseUnits, opt => opt.Ignore())
                .ForMember(x => x.LegalUnits, opt => opt.Ignore());

            CreateMap<ActivityM, Activity>()
                .ForMember(x => x.Id, x => x.Ignore())
                .ForMember(x => x.IdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.UpdatedDate, x => x.UseValue(DateTime.Now));


            //            CreateMap<ActivityCreateM, Activity>()
            //                .ForMember(x => x.IdDate, x => x.UseValue(DateTime.Now))
            //                .ForMember(x => x.UpdatedDate, x => x.UseValue(DateTime.Now))
            //                .ForMember(x => x.ActivitiesUnits, x => x.Ignore());
            //            CreateMap<ActivityEditM, Activity>()
            //                .ForMember(x => x.UpdatedDate, x => x.UseValue(DateTime.Now))
            //                .ForMember(x => x.ActivitiesUnits, x => x.Ignore());

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

        }

        private void HistoryMaping()
        {
            MapStatisticalUnit<LegalUnit>();
            MapStatisticalUnit<LocalUnit>();
            MapStatisticalUnit<EnterpriseUnit>();
            CreateMap<EnterpriseGroup, EnterpriseGroup>();
        }
        
        private void MapStatisticalUnit<T>() where T : StatisticalUnit
        {
            CreateMap<T, T>()
                .ForMember(v => v.Activities, v => v.Ignore())
                .ForMember(v => v.ActivitiesUnits,
                v => v.MapFrom(
                    x => x.ActivitiesUnits.Select(z => new ActivityStatisticalUnit() {ActivityId = z.ActivityId})
                ));
        }
    }
}