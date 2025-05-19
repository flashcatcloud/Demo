package model

import (
	"database/sql"

	"github.com/gin-gonic/gin"
	"github.com/XSAM/otelsql"
	semconv "go.opentelemetry.io/otel/semconv/v1.28.0"
)

var db *sql.DB

func Init() {
	initMysql()
}

func initMysql() {
	var err error
	// 你可以用环境变量配置这些参数
	dsn := "root:1234@tcp(127.0.0.1:3306)/testdb?parseTime=true"
	db, err = otelsql.Open("mysql", dsn, otelsql.WithAttributes(
		semconv.DBSystemMySQL,
	))
	if err != nil {
		panic(err)
	}
	// 建表
	createTable := `
	CREATE TABLE IF NOT EXISTS users (
		id BIGINT AUTO_INCREMENT PRIMARY KEY,
		name VARCHAR(64) NOT NULL,
		gender VARCHAR(8),
		phone VARCHAR(32) NOT NULL,
		email VARCHAR(128),
		age INT,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`
	if _, err := db.Exec(createTable); err != nil {
		panic(err)
	}
}

type User struct {
	Id        int64  `json:"id"`
	Name      string `json:"name"`
	Gender    string `json:"gender"`
	Phone     string `json:"phone"`
	Email     string `json:"email"`
	Age       int    `json:"age"`
	CreatedAt int64  `json:"created_at"`
}

func CreateUser(c *gin.Context) {
	var user User
	if err := c.ShouldBindJSON(&user); err != nil {
		c.JSON(400, gin.H{"error": "invalid request"})
		return
	}
	if user.Name == "" || user.Phone == "" {
		c.JSON(400, gin.H{"error": "name and phone required"})
		return
	}
	res, err := db.Exec("INSERT INTO users (name, gender, phone, email, age) VALUES (?, ?, ?, ?, ?)",
		user.Name, user.Gender, user.Phone, user.Email, user.Age)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	user.Id, _ = res.LastInsertId()
	c.JSON(200, user)
}

func GetUser(c *gin.Context) {
	name := c.Query("name")
	phone := c.Query("phone")
	if name == "" && phone == "" {
		c.JSON(400, gin.H{"error": "name or phone required"})
		return
	}
	var user User
	var row *sql.Row
	if name != "" && phone != "" {
		row = db.QueryRow("SELECT id, name, gender, phone, email, age, created_at FROM users WHERE name=? AND phone=? LIMIT 1", name, phone)
	} else if name != "" {
		row = db.QueryRow("SELECT id, name, gender, phone, email, age, created_at FROM users WHERE name=? LIMIT 1", name)
	} else {
		row = db.QueryRow("SELECT id, name, gender, phone, email, age, created_at FROM users WHERE phone=? LIMIT 1", phone)
	}
	err := row.Scan(&user.Id, &user.Name, &user.Gender, &user.Phone, &user.Email, &user.Age, &user.CreatedAt)
	if err != nil {
		c.JSON(404, gin.H{"error": "user not found"})
		return
	}
	c.JSON(200, user)
}

func ListUsers(c *gin.Context) {
	rows, err := db.Query("SELECT id, name, gender, phone, email, age, created_at FROM users ORDER BY created_at DESC LIMIT 100")
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()
	users := []User{}
	for rows.Next() {
		var user User
		if err := rows.Scan(&user.Id, &user.Name, &user.Gender, &user.Phone, &user.Email, &user.Age, &user.CreatedAt); err == nil {
			users = append(users, user)
		}
	}
	c.JSON(200, users)
}
