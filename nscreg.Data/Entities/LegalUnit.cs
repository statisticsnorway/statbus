using System;
using System.ComponentModel.DataAnnotations.Schema;

namespace nscreg.Data.Entities
{
    [Table("LegalUnit")]
    public class LegalUnit : StatisticalUnit
    {
        public int EnterpriseRegId { get; set; }    //	ID of Enterprise to which the Legal Unit is associated
        public DateTime EntRegIdDate { get; set; }  //	Date of association with enterprise
        public string Founders { get; set; }    //	
        public string Owner { get; set; }   //	
        public bool Market { get; set; }  //	Whether the unit is market/non-market (In Kyrgyzstan this is probably whether it is self financed versus state budget financed..)
        public string LegalForm { get; set; }   //	legal form code
        public string InstSectorCode { get; set; }  //	Institutional sector code (see Annex 3)
        public string TotalCapital { get; set; }    //	total 5 fields (sums up the next ones) 
        public string MunCapitalShare { get; set; } //	
        public string StateCapitalShare { get; set; }   //	
        public string PrivCapitalShare { get; set; }    //	
        public string ForeignCapitalShare { get; set; } //	
        public string ForeignCapitalCurrency { get; set; }  //	
        public string ActualMainActivity1 { get; set; } //	Main activity as perceived by the NSO using current version of classification
        public string ActualMainActivity2 { get; set; } //	Main activity as perceived by the NSO. To be used during transition to new activity classification version
        public string ActualMainActivityDate { get; set; }	//	
    }
}
