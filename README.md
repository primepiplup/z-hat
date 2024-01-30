```
 ______         _           _
|___  /        | |         | |
   / /_____ ___| |__   __ _| |_
  / /______/ __| '_ \ / _' | __|
./ /___   | (__| | | | (_| | |_
\_____/    \___|_| |_|\__,_|\__|
```


# Z-hat (Zig chat)
This chat application provides raw TCP message sending using a server/client model.
Expected IP address and port are compiled into the program at build.
It was written to learn the zig programming language as well as getting an understanding of how sockets are used at a lower level.

## Expected use
Due to communications being unsecured it is expected that communications should occur on a local network, and that no important information should be shared using the application.
One person should run the server application and share the used config.zig with anyone who will use the server. These users should compile the client with the config.zig file present in the directory.

## Build
The build.zig file contains build steps that allow for selective compilation of either the server or client using:
`zig build server` or `zig build client`
You can also choose to run the desired program using:
`zig build run_server` or `zig build run_client`

## Limitations
The communications occur unencrypted/unsecured using TCP stream sockets.
A misconfigured client (compiled with different configuration) can cause problems when communicating with a server.
