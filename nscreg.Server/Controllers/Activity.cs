using Microsoft.AspNetCore.Mvc;
using nscreg.Data;
using nscreg.Server.Models.StatUnits.Create;
using nscreg.Server.Models.StatUnits.Edit;
using nscreg.Server.Services;

namespace nscreg.Server.Controllers
{
    [Route("api/[controller]")]
    public class ActivityController : Controller
    {
        public ActivityService Service { get; }

        public ActivityController(NSCRegDbContext context)
        {
            Service = new ActivityService(context);
        }

        [HttpPost]
        public NoContentResult CreateActivity([FromBody] ActivityCreateM data)
        {
            Service.Create(data);
            return NoContent();
        }

        [HttpGet("{activityId}")]
        public IActionResult GetActivity(int activityId) => Ok(Service.GetActivityById(activityId));

        [HttpGet("unit/{unitId}")]
        public IActionResult GetUnitActivities(int unitId) => Ok(Service.GetUnitActivities(unitId));

        [HttpGet]
        public IActionResult GetAllActivities() => Ok(Service.GetAllActivities());

        [HttpPut]
        public IActionResult EditActivity([FromBody] ActivityEditM data)
        {
            Service.Update(data);
            return NoContent();
        }

        [HttpDelete("{id}")]
        public IActionResult DeleteActivity(int id)
        {
            Service.Delete(id);
            return NoContent();
        }
    }
}