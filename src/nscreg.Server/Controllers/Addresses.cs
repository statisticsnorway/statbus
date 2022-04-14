using System.Threading.Tasks;
using AutoMapper;
using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Server.Common.Models.Addresses;
using nscreg.Server.Common.Services;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Server.Core.Authorize;

namespace nscreg.Server.Controllers
{
    /// <summary>
    ///  Address controller
    /// </summary>
    [Route("api/[controller]")]
    public class AddressesController : Controller
    {
        private readonly IAddressService _addressService;

        public AddressesController(IAddressService addressService)
        {
            _addressService = addressService;
        }
        /// <summary>
        /// Method that returns a list of all addresses
        /// </summary>
        /// <param name="page">Page</param>
        /// <param name="pageSize">Page size</param>
        /// <param name="searchStr"></param>
        /// <returns></returns>
        // GET: api/address
        [HttpGet]
        [SystemFunction(SystemFunctions.AddressView)]
        public async Task<IActionResult> GetAll(int page = 1, int pageSize = 4, string searchStr = null) =>
            Ok(await _addressService.GetAsync(page, pageSize, x => searchStr == null || x.AddressPart1.Contains(searchStr)));

        /// <summary>
        /// Method returning a specific address
        /// </summary>
        /// <param name="id">id address</param>
        /// <returns></returns>
        // GET api/address/5
        [HttpGet("{id:int}")]
        [SystemFunction(SystemFunctions.AddressView)]
        public async Task<IActionResult> Get(int id) => Ok(await _addressService.GetByIdAsync(id));

        /// <summary>
        /// Address Creation Method
        /// </summary>
        /// <param name="model">address model</param>
        /// <returns></returns>
        // POST api/address
        [HttpPost]
        [SystemFunction(SystemFunctions.AddressCreate)]
        public async Task<IActionResult> Post([FromBody]AddressModel model)
        {
            var address = await _addressService.CreateAsync(model);
            return Created($"api/address/{address.Id}", address);
        }

        /// <summary>
        /// Address Change Method
        /// </summary>
        /// <param name="id">address id</param>
        /// <param name="model">address model</param>
        /// <returns></returns>
        // PUT api/address/5
        [HttpPut("{id}")]
        [SystemFunction(SystemFunctions.AddressEdit)]
        public async Task<IActionResult> Put(int id, [FromBody]AddressModel model)
        {
            await _addressService.UpdateAsync(id, model);
            return NoContent();
        }
        /// <summary>
        /// Address Removal Method
        /// </summary>
        /// <param name="id"></param>
        /// <returns></returns>
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
