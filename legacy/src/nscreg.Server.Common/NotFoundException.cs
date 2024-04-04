using System;

namespace nscreg.Server.Common
{
    /// <summary>
    /// Class handler "Not found" exception
    /// </summary>
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
