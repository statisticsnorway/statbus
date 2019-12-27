using System;
using Newtonsoft.Json;

namespace nscreg.Server.Common
{
    /// <summary>
    /// Bad exception class handler
    /// </summary>
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

        public BadRequestException(string localizedKey, Exception inner, params object[] parameters)
            : base(JsonConvert.SerializeObject(new {LocalizedKey = localizedKey, Parameters = parameters}), inner)
        {
        }
    }
}
