namespace nscreg.Utilities.Configuration
{
    /// <summary>
    /// Класс настройки соединения
    /// </summary>
    public class ConnectionSettings
    {
        public string ConnectionString { get; set; }
        public bool UseInMemoryDataBase { get; set; }
    }
}
