using System;

namespace nscreg.Data.Entities
{
    public class EnterpriseUnit : StatisticalUnit
    {
        public int EntGroupId { get; set; } //	ID of enterprise group of which the unit belongs
        public DateTime EntGroupIdDate { get; set; }    //	Date of assosciation with enterprise group
        public bool Commercial { get; set; }  //	Indicator for non-commercial activity (marked/non-marked?)
        public string InstSectorCode { get; set; }  //	Institutional sector code (see Annex 3)
        public string TotalCapital { get; set; }    //	total 5 fields (sums up the next ones) 
        public string MunCapitalShare { get; set; } //	
        public string StateCapitalShare { get; set; }   //	
        public string PrivCapitalShare { get; set; }    //	
        public string ForeignCapitalShare { get; set; } //	
        public string ForeignCapitalCurrency { get; set; }  //	
        public string ActualMainActivity1 { get; set; } //	Main activity as perceived by the NSO using current version of classification
        public string ActualMainActivity2 { get; set; } //	Main activity as perceived by the NSO. To be used during transition to new activity classification version
        public string ActualMainActivityDate { get; set; }  //	
        public string EntGroupRole { get; set; }	//	Role of enterprise within enterprise group (Management/control unit, global group head (controlling unit), Global decision centre (managing unit), highest level consolidation unit or “other”
    }
}
