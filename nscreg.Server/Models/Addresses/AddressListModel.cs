using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace nscreg.Server.Models.Addresses
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
