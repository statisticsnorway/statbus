using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Services
{
    public class SampleFrameService : ISampleFrameService
    {
        private readonly nscreg.Services.SampleFrames.SampleFrameService _service;

        public SampleFrameService(NSCRegDbContext context)
        {
            _service = new nscreg.Services.SampleFrames.SampleFrameService(context);
        }

        public async Task Create(SFExpression sfExpression)
        {
            await _service.CreateAsync(sfExpression);
        }

        public async Task Edit(SFExpression sfExpression)
        {
            throw new System.NotImplementedException();
        }

        public async void Delete(int id)
        {
            throw new System.NotImplementedException();
        }
    }
}
