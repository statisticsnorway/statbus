using System;

namespace nscreg.Server.Core
{
    public class BadRequestException : Exception
    {
        public BadRequestException(string message)
        : base(message)
        {
        }

        public BadRequestException(string message, Exception inner)
        : base(message, inner)
        {
        }
    }
}
