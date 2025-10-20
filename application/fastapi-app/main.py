from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import os
import boto3
import pymysql
import logging
from datetime import datetime
import socket

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Resilient Web Application",
    description="Multi-region resilient web application with automatic failover",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "unknown")
REGION = os.getenv("REGION", "unknown")
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_USER = os.getenv("DB_USER", "admin")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME = os.getenv("DB_NAME", "webapp")

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Welcome to the Resilient Web Application",
        "environment": ENVIRONMENT,
        "region": REGION,
        "hostname": socket.gethostname(),
        "timestamp": datetime.utcnow().isoformat()
    }

@app.get("/health")
async def health_check():
    """Health check endpoint for load balancer"""
    try:
        # Check database connectivity
        db_status = await check_database()
        
        # Check S3 connectivity
        s3_status = await check_s3()
        
        status = "healthy" if db_status and s3_status else "unhealthy"
        
        return {
            "status": status,
            "environment": ENVIRONMENT,
            "region": REGION,
            "hostname": socket.gethostname(),
            "timestamp": datetime.utcnow().isoformat(),
            "checks": {
                "database": "ok" if db_status else "error",
                "s3": "ok" if s3_status else "error"
            }
        }
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return JSONResponse(
            status_code=503,
            content={
                "status": "unhealthy",
                "error": str(e),
                "environment": ENVIRONMENT,
                "region": REGION,
                "timestamp": datetime.utcnow().isoformat()
            }
        )

@app.get("/api/status")
async def get_status():
    """Get application status"""
    return {
        "application": "Resilient Web Application",
        "environment": ENVIRONMENT,
        "region": REGION,
        "hostname": socket.gethostname(),
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0"
    }

@app.get("/api/data")
async def get_data():
    """Get sample data from database"""
    try:
        connection = pymysql.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            charset='utf8mb4',
            cursorclass=pymysql.cursors.DictCursor
        )
        
        with connection:
            with connection.cursor() as cursor:
                # Create table if it doesn't exist
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS sample_data (
                        id INT AUTO_INCREMENT PRIMARY KEY,
                        message VARCHAR(255),
                        region VARCHAR(50),
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                
                # Insert sample data
                cursor.execute(
                    "INSERT INTO sample_data (message, region) VALUES (%s, %s)",
                    (f"Hello from {REGION}", REGION)
                )
                connection.commit()
                
                # Fetch recent data
                cursor.execute(
                    "SELECT * FROM sample_data ORDER BY created_at DESC LIMIT 10"
                )
                results = cursor.fetchall()
                
        return {
            "data": results,
            "region": REGION,
            "timestamp": datetime.utcnow().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Database error: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

async def check_database():
    """Check database connectivity"""
    try:
        connection = pymysql.connect(
            host=DB_HOST,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            connect_timeout=5
        )
        connection.close()
        return True
    except Exception as e:
        logger.error(f"Database check failed: {str(e)}")
        return False

async def check_s3():
    """Check S3 connectivity"""
    try:
        s3_client = boto3.client('s3', region_name=REGION)
        s3_client.list_buckets()
        return True
    except Exception as e:
        logger.error(f"S3 check failed: {str(e)}")
        return False

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)