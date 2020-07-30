# escape=`

# Use the latest Windows Server.
FROM mcr.microsoft.com/windows/servercore:1809  AS builder

USER ContainerAdministrator

#################################################
# Install Chocolatey
#################################################

RUN powershell.exe Invoke-WebRequest `
  -Uri https://chocolatey.org/install.ps1 `
  -OutFile C:\chocolatey-install.ps1
RUN powershell.exe `
  -ExecutionPolicy bypass `
  -InputFormat none `
  -NoProfile `
  C:\chocolatey-install.ps1
RUN set "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"

#################################################
# Base Dependencies
#################################################

RUN choco install --yes --no-progress mingw git make
RUN choco install --yes --no-progress golang --version=1.12

# Put the path before the other paths so that 
# MinGW shadows Windows commands.
RUN set "C:\ProgramData\chocolatey\lib\mingw\tools\install\mingw\bin;PATH=%PATH%"

#################################################
# Visual C++ Build Tools
#################################################

# Download the Build Tools bootstrapper.
ADD https://aka.ms/vs/16/release/vs_buildtools.exe C:\TEMP\vs_buildtools.exe

# Install Build Tools with the Microsoft.VisualStudio.Workload.AzureBuildTools workload, excluding workloads and components with known issues.
RUN C:\TEMP\vs_buildtools.exe --quiet --wait --norestart --nocache `
    --installPath C:\BuildTools `
    --add Microsoft.VisualStudio.Workload.AzureBuildTools `
    --remove Microsoft.VisualStudio.Component.Windows10SDK.10240 `
    --remove Microsoft.VisualStudio.Component.Windows10SDK.10586 `
    --remove Microsoft.VisualStudio.Component.Windows10SDK.14393 `
    --remove Microsoft.VisualStudio.Component.Windows81SDK `
 || IF "%ERRORLEVEL%"=="3010" EXIT 0

###########################################################################
# Restore the default Windows shell for correct batch processing.
###########################################################################
 
SHELL ["powershell.exe", "-ExecutionPolicy", "Bypass", "-Command"]

COPY Makefile go.* *.go /go/src/github.com/newrelic/newrelic-fluent-bit-output/
COPY config/ /go/src/github.com/newrelic/newrelic-fluent-bit-output/config
COPY nrclient/ /go/src/github.com/newrelic/newrelic-fluent-bit-output/nrclient
COPY record/ /go/src/github.com/newrelic/newrelic-fluent-bit-output/record
COPY utils/ /go/src/github.com/newrelic/newrelic-fluent-bit-output/utils

ENV SOURCE docker

# TODO set GOPATH currectly

RUN go get github.com/fluent/fluent-bit-go/output

WORKDIR /go/src/github.com/newrelic/newrelic-fluent-bit-output

RUN make all

###########################################################################
# Windows Nanoserver:1809
###########################################################################

FROM mcr.microsoft.com/windows/nanoserver:1809-amd64

USER ContainerAdministrator

RUN mkdir C:\\Temp

#TODO set version veribles

RUN curl https://fluentbit.io/releases/1.5/td-agent-bit-1.5.1-win64.zip -o /Temp/td-agent-bit-1.5.1-win64.zip

WORKDIR /fluent-bit

RUN tar -xf /Temp/td-agent-bit-1.5.1-win64.zip --strip=1 td-agent-bit-1.5.1-win64

RUN rmdir C:\\Temp /s /q

COPY --from=builder /go/src/github.com/newrelic/newrelic-fluent-bit-output/out_newrelic.so /fluent-bit/bin/
COPY *.conf /fluent-bit/etc/

CMD ["cmd", "/c", "/fluent-bit/bin/fluent-bit.exe", "-c", "/fluent-bit/conf/fluent-bit.conf", "-e", "/fluent-bit/bin/out_newrelic.so" ]
