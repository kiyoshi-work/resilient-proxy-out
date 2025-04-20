#!/usr/bin/env node

const axios = require('axios');
const { performance } = require('perf_hooks');
const { HttpsProxyAgent } = require('https-proxy-agent');

const RUNS = 10;
let avgTimesTotal = 0;

console.log(`Start benchmark ${RUNS} times...`);
const startTime = performance.now();
const instance = axios.create({
  proxy: false,
  httpsAgent: new HttpsProxyAgent(
    'http://xruolauf-US-GB-rotate:1cysf56k28h3@p.webshare.io:80',
    {
      keepAlive: true,
      keepAliveMsecs: 1000,
      maxSockets: 5
    }
  ),
  headers: {
    'Content-Type': 'application/json',
    'Connection': 'keep-alive'
  }
});
const endTime = performance.now();
const totalTime = (endTime - startTime) / 1000;
console.log(`Total time: ${totalTime.toFixed(6)}s`);

async function runBenchmark(runNumber) {
  console.log(`Chạy lần thứ ${runNumber}...`);
  
  const startTime = performance.now();
  const dnsStartTime = startTime;
  
  try {
    // const response = await instance.post('https://api.hyperliquid.xyz/info', {
    //   type: "clearinghouseState", 
    //   user: "0xf6779a38203d47718139d3254237c43201493f00"
    // });
    const response = await instance.get('https://ipinfo.io/');
    
    const endTime = performance.now();
    const totalTime = (endTime - startTime) / 1000;
        console.log(`Total time: ${totalTime.toFixed(6)}s`);
    

    console.log("Response content:");
    console.log(JSON.stringify(response.data, null, 2));
    console.log("----------------------------------------");
    
    return totalTime;
  } catch (error) {
    console.error(`Error in run ${runNumber}:`, error.message);
    return false;
  }
}

async function main() {
  let successfulRuns = 0;
  
  for (let i = 1; i <= RUNS; i++) {
    const success = await runBenchmark(i);
    if (success) successfulRuns++;
    avgTimesTotal += success;
  }
  
  const actualRuns = successfulRuns > 0 ? successfulRuns : 1;
    
  console.log("Benchmark result:");
  console.log(`Total successful runs: ${successfulRuns}/${RUNS}`);
  console.log("Average time:");
  console.log(`Total time: ${(avgTimesTotal / actualRuns).toFixed(4)}s`);
}

main().catch(error => {
  console.error('Error:', error);
  process.exit(1);
});
