using System;

namespace nscreg.Server.Models.StatisticalUnit
{
    public interface IStatisticalUnitsM
    {
        string Name { get; set; }
        string AddressPart1 { get; set; }
        string AddressPart2 { get; set; }
        string AddressPart3 { get; set; }
        string AddressPart4 { get; set; }
        string AddressPart5 { get; set; }
        string GeographicalCodes { get; set; }
        string GpsCoordinates { get; set; }
        string ActualAddressPart1 { get; set; }
        string ActualAddressPart2 { get; set; }
        string ActualAddressPart3 { get; set; }
        string ActualAddressPart4 { get; set; }
        string ActualAddressPart5 { get; set; }
        string ActualGeographicalCodes { get; set; }
        string ActualGpsCoordinates { get; set; }
    }
}
