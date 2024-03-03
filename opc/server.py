import asyncio
import logging
import random
from asyncua import ua, Server


async def main():

    server = Server()
    await server.init()
    server.set_endpoint("opc.tcp://0.0.0.0:4840")
    server.set_server_name("Example OPC-UA Server")
    # set all possible endpoint policies for clients to connect through
    server.set_security_policy(
        [
            ua.SecurityPolicyType.NoSecurity,
            ua.SecurityPolicyType.Basic256Sha256_SignAndEncrypt,
            ua.SecurityPolicyType.Basic256Sha256_Sign,
        ]
    )

    # setup our own namespace
    uri = "http://examples.jonboh.github.com" # not a valid url
    idx = await server.register_namespace(uri)

    sensors = await server.nodes.objects.add_object(idx, "Sensors")
    temperature = await sensors.add_variable(idx, "Temperature", 0.0)
    pressure = await sensors.add_variable(idx, "Pressure", 0.0)
    slow_sensor = await sensors.add_variable(idx, "SlowSensor", 0.0)

    # starting!
    async with server:
        print("Available loggers are: ", logging.Logger.manager.loggerDict.keys())

        counter = 0
        temperature_value = 0
        pressure_value = 0
        slow_sensor_value = 0

        while True:
            print("tick")
            await asyncio.sleep(0.2)
            temperature_value += random.uniform(-1, 1)
            await server.write_attribute_value(temperature.nodeid,
                                               ua.DataValue(temperature_value))
            if counter%10==0:
                print("tick_pressure")
                pressure_value +=random.uniform(-3.1, 3.1)
                await server.write_attribute_value(pressure.nodeid,
                                                   ua.DataValue(pressure_value))
            if counter%40==0:
                print("tick_slow")
                slow_sensor_value +=random.uniform(-6.3, 6.3)
                await server.write_attribute_value(slow_sensor.nodeid,
                                                   ua.DataValue(slow_sensor_value))
            counter+=1


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())

