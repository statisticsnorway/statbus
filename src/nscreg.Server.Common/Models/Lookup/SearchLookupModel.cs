namespace nscreg.Server.Common.Models.Lookup
{
    /// <summary>
    /// Search model
    /// </summary>
    public class SearchLookupModel
    {
        public int Page { get; set; }
        public int PageSize { get; set; }
        public string Wildcard { get; set; }
    }
}
