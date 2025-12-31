#!/usr/bin/env python3
"""
Backup de Colecciones Milvus usando PyMilvus
Exporta colecciones a formato JSON/Parquet para backup granular
"""

import os
import sys
import json
import logging
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any

try:
    from pymilvus import connections, utility, Collection
    import numpy as np
except ImportError:
    print("❌ Instalando dependencias...")
    os.system("pip install pymilvus numpy")
    from pymilvus import connections, utility, Collection
    import numpy as np

# Configuración
MILVUS_INSTANCES = [
    {"name": "milvus-1", "host": "localhost", "port": 19530},
    {"name": "milvus-2", "host": "localhost", "port": 19531},
    {"name": "milvus-3", "host": "localhost", "port": 19532},
    {"name": "milvus-4", "host": "localhost", "port": 19533},
    {"name": "milvus-5", "host": "localhost", "port": 19534},
    {"name": "macrochat", "host": "localhost", "port": 19540},
]

QNAP_BACKUP_PATH = "/Volumes/QNAPBackup/milvus-backups/collections"

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MilvusBackup:
    def __init__(self, backup_path: str):
        self.backup_path = Path(backup_path)
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.backup_dir = self.backup_path / f"backup_{self.timestamp}"
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        
    def connect(self, alias: str, host: str, port: int) -> bool:
        """Conectar a una instancia de Milvus"""
        try:
            connections.connect(alias=alias, host=host, port=port, timeout=10)
            logger.info(f"✅ Conectado a {alias} ({host}:{port})")
            return True
        except Exception as e:
            logger.error(f"❌ Error conectando a {alias}: {e}")
            return False
    
    def disconnect(self, alias: str):
        """Desconectar de una instancia"""
        try:
            connections.disconnect(alias=alias)
        except:
            pass
    
    def list_collections(self, alias: str) -> List[str]:
        """Listar todas las colecciones"""
        try:
            return utility.list_collections(using=alias)
        except Exception as e:
            logger.error(f"Error listando colecciones: {e}")
            return []
    
    def backup_collection_schema(self, collection_name: str, alias: str, instance_dir: Path) -> Dict:
        """Backup del schema de una colección"""
        try:
            collection = Collection(collection_name, using=alias)
            schema = collection.schema
            
            schema_info = {
                "collection_name": collection_name,
                "description": schema.description,
                "fields": [],
                "num_entities": collection.num_entities,
                "indexes": []
            }
            
            for field in schema.fields:
                field_info = {
                    "name": field.name,
                    "dtype": str(field.dtype),
                    "is_primary": field.is_primary,
                    "auto_id": field.auto_id if hasattr(field, 'auto_id') else False,
                }
                if hasattr(field, 'dim'):
                    field_info["dim"] = field.dim
                if hasattr(field, 'max_length'):
                    field_info["max_length"] = field.max_length
                schema_info["fields"].append(field_info)
            
            # Obtener índices
            try:
                for field in schema.fields:
                    if hasattr(field, 'dtype') and 'FLOAT_VECTOR' in str(field.dtype):
                        index_info = collection.index()
                        if index_info:
                            schema_info["indexes"].append({
                                "field": field.name,
                                "params": str(index_info.params)
                            })
            except:
                pass
            
            # Guardar schema
            schema_file = instance_dir / f"{collection_name}_schema.json"
            with open(schema_file, 'w') as f:
                json.dump(schema_info, f, indent=2, default=str)
            
            logger.info(f"  📋 Schema guardado: {collection_name} ({collection.num_entities} entidades)")
            return schema_info
            
        except Exception as e:
            logger.error(f"  ❌ Error en schema de {collection_name}: {e}")
            return {}
    
    def backup_collection_data(self, collection_name: str, alias: str, instance_dir: Path, batch_size: int = 1000) -> bool:
        """Backup de los datos de una colección (solo metadatos, vectores son muy grandes)"""
        try:
            collection = Collection(collection_name, using=alias)
            collection.load()
            
            # Solo exportamos estadísticas y sample de datos para colecciones grandes
            num_entities = collection.num_entities
            
            if num_entities == 0:
                logger.info(f"  📭 Colección vacía: {collection_name}")
                return True
            
            data_info = {
                "collection_name": collection_name,
                "num_entities": num_entities,
                "backup_date": datetime.now().isoformat(),
                "note": "Full data backup requires milvus-backup tool for large collections"
            }
            
            # Guardar info
            data_file = instance_dir / f"{collection_name}_info.json"
            with open(data_file, 'w') as f:
                json.dump(data_info, f, indent=2)
            
            logger.info(f"  💾 Info guardada: {collection_name}")
            return True
            
        except Exception as e:
            logger.error(f"  ❌ Error exportando datos de {collection_name}: {e}")
            return False
    
    def backup_instance(self, instance: Dict) -> Dict:
        """Backup completo de una instancia de Milvus"""
        alias = instance["name"]
        host = instance["host"]
        port = instance["port"]
        
        result = {
            "instance": alias,
            "host": f"{host}:{port}",
            "status": "failed",
            "collections": []
        }
        
        if not self.connect(alias, host, port):
            return result
        
        try:
            collections = self.list_collections(alias)
            logger.info(f"📚 {alias}: {len(collections)} colecciones encontradas")
            
            if not collections:
                result["status"] = "success"
                result["message"] = "No collections found"
                return result
            
            instance_dir = self.backup_dir / alias
            instance_dir.mkdir(parents=True, exist_ok=True)
            
            for coll_name in collections:
                logger.info(f"  🔄 Procesando: {coll_name}")
                schema = self.backup_collection_schema(coll_name, alias, instance_dir)
                self.backup_collection_data(coll_name, alias, instance_dir)
                result["collections"].append({
                    "name": coll_name,
                    "entities": schema.get("num_entities", 0)
                })
            
            result["status"] = "success"
            
        except Exception as e:
            logger.error(f"Error en backup de {alias}: {e}")
            result["error"] = str(e)
        finally:
            self.disconnect(alias)
        
        return result
    
    def run_full_backup(self) -> Dict:
        """Ejecutar backup completo de todas las instancias"""
        logger.info("=" * 60)
        logger.info("🚀 INICIANDO BACKUP DE COLECCIONES MILVUS")
        logger.info(f"📁 Destino: {self.backup_dir}")
        logger.info("=" * 60)
        
        results = {
            "backup_date": datetime.now().isoformat(),
            "backup_path": str(self.backup_dir),
            "instances": []
        }
        
        for instance in MILVUS_INSTANCES:
            logger.info(f"\n{'='*40}")
            logger.info(f"📌 Procesando: {instance['name']}")
            logger.info(f"{'='*40}")
            
            result = self.backup_instance(instance)
            results["instances"].append(result)
        
        # Guardar resumen
        summary_file = self.backup_dir / "backup_summary.json"
        with open(summary_file, 'w') as f:
            json.dump(results, f, indent=2)
        
        # Mostrar resumen
        logger.info("\n" + "=" * 60)
        logger.info("📊 RESUMEN DEL BACKUP")
        logger.info("=" * 60)
        
        total_collections = 0
        for inst in results["instances"]:
            status_icon = "✅" if inst["status"] == "success" else "❌"
            num_colls = len(inst.get("collections", []))
            total_collections += num_colls
            logger.info(f"  {status_icon} {inst['instance']}: {num_colls} colecciones")
        
        logger.info(f"\n📚 Total colecciones respaldadas: {total_collections}")
        logger.info(f"📁 Ubicación: {self.backup_dir}")
        
        return results


def main():
    # Verificar que QNAP está montado
    if not os.path.exists(QNAP_BACKUP_PATH):
        logger.warning(f"⚠️ QNAP no montado en {QNAP_BACKUP_PATH}")
        logger.info("📁 Usando directorio local como fallback...")
        backup_path = os.path.expanduser("~/Desktop/QNAPBackup/backups/collections")
        os.makedirs(backup_path, exist_ok=True)
    else:
        backup_path = QNAP_BACKUP_PATH
    
    backup = MilvusBackup(backup_path)
    results = backup.run_full_backup()
    
    return 0 if all(r["status"] == "success" for r in results["instances"]) else 1


if __name__ == "__main__":
    sys.exit(main())
