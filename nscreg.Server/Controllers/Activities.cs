using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class ActivitiesController : Controller
    {
        private readonly ActivityService _service;

        public ActivitiesController(NSCRegDbContext context)
        {
            _service = new ActivityService(context);
        }

        [HttpGet]
        public IActionResult GetAllActivities() => Ok(_service.GetAllActivities());

        [HttpGet("{activityId}")]
        public IActionResult GetActivity(int activityId) => Ok(_service.GetActivityById(activityId));

        [HttpGet("unit/{unitId}")]
        public IActionResult GetUnitActivities(int unitId) => Ok(_service.GetUnitActivities(unitId));

        [HttpPost]
        public IActionResult CreateActivity([FromBody] ActivityCreateM data)
        {
            _service.Create(data);
            return NoContent();
        }

        [HttpPut]
        public IActionResult EditActivity([FromBody] ActivityEditM data)
        {
            _service.Update(data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public IActionResult DeleteActivity(int id)
        {
            _service.Delete(id);
            return NoContent();
        }
    }
}
