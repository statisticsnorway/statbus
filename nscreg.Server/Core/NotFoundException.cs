using System;

namespace nscreg.Server.Core
{
    public class NotFoundException : Exception
    {
        public NotFoundException(string message)
        : base(message)
        {
        }

        public NotFoundException(string message, Exception inner)
        : base(message, inner)
        {
        }
    }
}
