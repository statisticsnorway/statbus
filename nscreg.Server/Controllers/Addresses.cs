using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.Addresses;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Core.Authorize;

// For more information on enabling Web API for empty projects, visit http://go.microsoft.com/fwlink/?LinkID=397860

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class AddressesController : Controller
    {
        private readonly IAddressService _addressService;

        public AddressesController(NSCRegDbContext context)
        {
            _addressService = new AddressService(context);
        }

        // GET: api/address
        [HttpGet]
        [SystemFunction(SystemFunctions.AddressView)]
        public async Task<IActionResult> GetAll(int page = 1, int pageSize = 4, string searchStr = null) =>
            Ok(await _addressService.GetAsync(page, pageSize, x => searchStr == null || x.AddressPart1.Contains(searchStr)));

        // GET api/address/5
        [HttpGet("{id:int}")]
        [SystemFunction(SystemFunctions.AddressView)]
        public async Task<IActionResult> Get(int id) => Ok(await _addressService.GetByIdAsync(id));

        // POST api/address
        [HttpPost]
        [SystemFunction(SystemFunctions.AddressCreate)]
        public async Task<IActionResult> Post([FromBody]AddressModel model)
        {
            var address = await _addressService.CreateAsync(model);
            return Created($"api/address/{address.Id}", address);
        }

        // PUT api/address/5
        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.AddressEdit)]
        public async Task<IActionResult> Put(int id, [FromBody]AddressModel model)
        {
            await _addressService.UpdateAsync(id, model);
            return NoContent();
        }

        // DELETE api/address/5
        [HttpDelete("{id}")]
        [SystemFunction(SystemFunctions.AddressDelete)]
        public async Task<IActionResult> Delete(int id)
        {
            await _addressService.DeleteAsync(id);
            return NoContent();
        }
    }
}
