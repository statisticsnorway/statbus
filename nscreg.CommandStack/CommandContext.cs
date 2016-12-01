using nscreg.Data;

namespace nscreg.CommandStack
{
    public class CommandContext
    {
        private readonly NSCRegDbContext _dbContext;

        public CommandContext(NSCRegDbContext dbContext)
        {
            _dbContext = dbContext;
        }
    }
}}
