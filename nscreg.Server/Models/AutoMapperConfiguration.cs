using System;
using AutoMapper;
using nscreg.Data.Entities;
using nscreg.Server.Models.StatisticalUnit.Edit;
using nscreg.Server.Models.StatisticalUnit.Submit;

namespace nscreg.Server.Models
{
    public class AutoMapperConfiguration
    {
        public static void Configure()
        {
            Mapper.Initialize(x =>
            {
                x.AddProfile<AutoMapperProfile>();
            });
        }
    }

    internal class AutoMapperProfile : Profile
    {
        public AutoMapperProfile()
        {
            CreateMap<LegalUnitSubmitM, LegalUnit>()
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
            CreateMap<LocalUnitSubmitM, LocalUnit>()
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
            CreateMap<EnterpriseUnitSubmitM, EnterpriseUnit>()
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
            CreateMap<EnterpriseGroupSubmitM, EnterpriseGroup>()
                .ForMember(x => x.RegIdDate, x => x.UseValue(DateTime.Now))
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
            CreateMap<LegalUnitEditM, LegalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
            CreateMap<LocalUnitEditM, LocalUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
            CreateMap<EnterpriseUnitEditM, EnterpriseUnit>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
            CreateMap<EnterpriseGroupEditM, EnterpriseGroup>()
                .ForMember(x => x.Address, x => x.Ignore())
                .ForMember(x => x.ActualAddress, x => x.Ignore());
        }
    }
}
