using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace MockTor {
    class Program {
        static void Main(string[] args) {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string logDir = Path.Combine(appDir, "logs");
            Directory.CreateDirectory(logDir);
            string logPath = Path.Combine(logDir, "tor-notice.log");
            
            // Write bootstrap log
            string now = DateTime.Now.ToString("[yyyy-MM-dd HH:mm:ss]");
            File.AppendAllText(logPath, now + " [notice] Tor v0.4.8.12 running on Windows\r\n");
            File.AppendAllText(logPath, now + " [notice] Bootstrapped 100% (done): Done\r\n");
            
            // Start control port listener
            TcpListener listener = new TcpListener(IPAddress.Loopback, 9051);
            listener.Start();
            Console.WriteLine("Mock Tor control port listening on 127.0.0.1:9051");
            
            while (true) {
                TcpClient client = listener.AcceptTcpClient();
                NetworkStream stream = client.GetStream();
                StreamReader reader = new StreamReader(stream);
                StreamWriter writer = new StreamWriter(stream);
                writer.AutoFlush = true;
                
                writer.WriteLine("250 OK");
                
                string line;
                while ((line = reader.ReadLine()) != null) {
                    if (line.StartsWith("AUTHENTICATE")) {
                        writer.WriteLine("250 OK");
                    } else if (line.StartsWith("GETINFO version")) {
                        writer.WriteLine("250-version=0.4.8.12");
                        writer.WriteLine("250 OK");
                    } else if (line.StartsWith("GETINFO traffic")) {
                        writer.WriteLine("250-traffic/read=1048576");
                        writer.WriteLine("250-traffic/written=524288");
                        writer.WriteLine("250 OK");
                    } else if (line.StartsWith("GETINFO uptime")) {
                        writer.WriteLine("250-uptime=3600");
                        writer.WriteLine("250 OK");
                    } else if (line.StartsWith("GETINFO circuit-status")) {
                        writer.WriteLine("250+circuit-status=");
                        writer.WriteLine("250 OK");
                    } else if (line.StartsWith("GETINFO ns/all")) {
                        writer.WriteLine("250+ns/all=");
                        writer.WriteLine("250 OK");
                    } else if (line == "SIGNAL NEWNYM") {
                        writer.WriteLine("250 OK");
                    } else {
                        writer.WriteLine("250 OK");
                    }
                }
                client.Close();
            }
        }
    }
}
