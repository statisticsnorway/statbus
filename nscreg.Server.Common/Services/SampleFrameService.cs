using System.Threading.Tasks;
using nscreg.Data;
using nscreg.Server.Common.Services.Contracts;
using nscreg.Utilities.Models.SampleFrame;

namespace nscreg.Server.Common.Services
{
    public class SampleFrameService : ISampleFrameService
    {
        private readonly NSCRegDbContext _context;
        private readonly nscreg.Services.SampleFrames.SampleFrameService _service;

        public SampleFrameService(NSCRegDbContext context)
        {
            _context = context;
            _service = new nscreg.Services.SampleFrames.SampleFrameService(context);
        }

        public async Task Create(Expression expression)
        {
            await _service.CreateAsync(expression);
        }

        public async Task Edit(Expression expression)
        {
            throw new System.NotImplementedException();
        }

        public async void Delete(int id)
        {
            throw new System.NotImplementedException();
        }
    }
}
