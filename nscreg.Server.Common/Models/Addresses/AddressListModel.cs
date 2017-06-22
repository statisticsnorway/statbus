using System.Collections.Generic;

namespace nscreg.Server.Common.Models.Addresses
{
    public class AddressListModel
    {
        public IList<AddressModel> Addresses { get; set; }

        public int TotalCount { get; set; }

        public int TotalPages { get; set; }

        public int CurrentPage { get; set; }

        public int PageSize { get; set; }
    }
}
