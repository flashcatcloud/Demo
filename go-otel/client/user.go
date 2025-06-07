package main

import (
	"log"
	"time"
	"context"
	"fmt"
	"net/http"
	"encoding/json"
	"bytes"
	"math/rand"
	"strings"

	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/attribute"
)

// 预定义的常见英文名字
var commonNames = []string{
	"James", "John", "Robert", "Michael", "William", "David", "Richard", "Joseph", "Thomas", "Charles",
	"Mary", "Patricia", "Jennifer", "Linda", "Elizabeth", "Barbara", "Susan", "Jessica", "Sarah", "Karen",
	"Christopher", "Daniel", "Matthew", "Anthony", "Mark", "Donald", "Steven", "Paul", "Andrew", "Joshua",
	"Kenneth", "Kevin", "Brian", "George", "Timothy", "Ronald", "Jason", "Edward", "Jeffrey", "Ryan",
	"Jacob", "Gary", "Nicholas", "Eric", "Jonathan", "Stephen", "Larry", "Justin", "Scott", "Brandon",
	"Benjamin", "Samuel", "Gregory", "Alexander", "Patrick", "Frank", "Raymond", "Jack", "Dennis", "Jerry",
}

// User 用户结构体
type User struct {
	Name      string `json:"name"`
	Gender    string `json:"gender"`
	Phone     string `json:"phone"`
	Email     string `json:"email"`
	Age       int    `json:"age"`
	ID        int64  `json:"id,omitempty"`
	CreatedAt int64  `json:"created_at,omitempty"`
}

func (c *Client) runUserRequests(ctx context.Context) {
	log.Println("开始发送用户相关请求...")

	// 先创建一些初始用户
	log.Println("创建初始用户...")
	for i := 0; i < 3; i++ {
		if err := c.createUser(ctx); err != nil {
			log.Printf("创建初始用户失败: %v", err)
		}
	}

	for {
		select {
		case <-ctx.Done():
			return
		default:
			// 每分钟执行10-20个请求
			numRequests := c.randomBetween(10, 20)
			log.Printf("本分钟将执行 %d 个用户请求", numRequests)

			sleepInterval := time.Duration(60*1000/numRequests) * time.Millisecond

			for i := 0; i < numRequests; i++ {
				// 随机选择请求类型
				requestType := c.randomBetween(1, 3)

				var err error
				switch requestType {
				case 1:
					err = c.createUser(ctx)
				case 2:
					err = c.randomUserQuery(ctx)
				case 3:
					err = c.listUsers(ctx)
				}

				if err != nil {
					log.Printf("用户请求失败: %v", err)
				}

				// 检查是否应该退出
				select {
				case <-ctx.Done():
					return
				case <-time.After(sleepInterval):
					// 继续下一个请求
				}
			}
		}
	}
}

func (c *Client) randomUserQuery(ctx context.Context) error {
	// 如果没有创建的用户，先创建一些用户
	if len(c.createdUsers) == 0 {
		log.Println("没有创建的用户，先创建一些用户...")
		for i := 0; i < 3; i++ {
			if err := c.createUser(ctx); err != nil {
				log.Printf("创建初始用户失败: %v", err)
			}
			time.Sleep(500 * time.Millisecond)
		}
	}

	if len(c.createdUsers) == 0 {
		return fmt.Errorf("仍然没有可用的用户")
	}

	// 随机选择一个用户
	userIdx := c.randomBetween(0, len(c.createdUsers)-1)
	user := c.createdUsers[userIdx]

	// 随机选择查询方式：按姓名或按电话
	if c.randomBetween(1, 2) == 1 {
		return c.getUserByName(ctx, user.Name)
	} else {
		return c.getUserByPhone(ctx, user.Phone)
	}
}

func (c *Client) getUserByPhone(ctx context.Context, phone string) error {
	ctx, span := c.tracer.Start(ctx, "client.getUserByPhone")
	defer span.End()

	span.SetAttributes(attribute.String("user.query.phone", phone))

	url := fmt.Sprintf("%s/user?phone=%s", c.serverURL, phone)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		span.SetStatus(codes.Error, "failed to create request")
		span.RecordError(err)
		return fmt.Errorf("创建查询用户请求失败: %w", err)
	}

	startTime := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		span.SetStatus(codes.Error, "request failed")
		span.RecordError(err)
		return fmt.Errorf("查询用户请求失败: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(startTime)
	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.Float64("http.duration_ms", float64(duration.Nanoseconds())/1e6),
	)

	if resp.StatusCode == http.StatusOK {
		log.Printf("查询用户成功 - 电话: %s, 耗时: %.3fms", phone, float64(duration.Nanoseconds())/1e6)
	} else if resp.StatusCode == http.StatusNotFound {
		span.SetAttributes(attribute.Bool("user.found", false))
		log.Printf("用户未找到 - 电话: %s", phone)
	} else {
		span.SetStatus(codes.Error, "non-200 status code")
		return fmt.Errorf("查询用户失败，状态码: %d", resp.StatusCode)
	}

	return nil
}

func (c *Client) listUsers(ctx context.Context) error {
	ctx, span := c.tracer.Start(ctx, "client.listUsers")
	defer span.End()

	url := c.serverURL + "/users"
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		span.SetStatus(codes.Error, "failed to create request")
		span.RecordError(err)
		return fmt.Errorf("创建列表用户请求失败: %w", err)
	}

	startTime := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		span.SetStatus(codes.Error, "request failed")
		span.RecordError(err)
		return fmt.Errorf("列表用户请求失败: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(startTime)
	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.Float64("http.duration_ms", float64(duration.Nanoseconds())/1e6),
	)

	if resp.StatusCode == http.StatusOK {
		// 解析用户列表以获取用户数量
		var users []User
		if err := json.NewDecoder(resp.Body).Decode(&users); err == nil {
			span.SetAttributes(attribute.Int("users.count", len(users)))
			log.Printf("列表用户成功 - 用户数量: %d, 耗时: %.3fms", len(users), float64(duration.Nanoseconds())/1e6)
		} else {
			log.Printf("列表用户成功 - 耗时: %.3fms", float64(duration.Nanoseconds())/1e6)
		}
	} else {
		span.SetStatus(codes.Error, "non-200 status code")
		return fmt.Errorf("列表用户失败，状态码: %d", resp.StatusCode)
	}

	return nil
}

func (c *Client) createUser(ctx context.Context) error {
	ctx, span := c.tracer.Start(ctx, "client.createUser")
	defer span.End()

	user := c.generateRandomUser()

	span.SetAttributes(
		attribute.String("user.name", user.Name),
		attribute.String("user.gender", user.Gender),
		attribute.String("user.phone", user.Phone),
		attribute.Int("user.age", user.Age),
	)

	userJSON, err := json.Marshal(user)
	if err != nil {
		span.SetStatus(codes.Error, "failed to marshal user")
		span.RecordError(err)
		return fmt.Errorf("序列化用户数据失败: %w", err)
	}

	url := c.serverURL + "/user"
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(userJSON))
	if err != nil {
		span.SetStatus(codes.Error, "failed to create request")
		span.RecordError(err)
		return fmt.Errorf("创建用户请求失败: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	startTime := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		span.SetStatus(codes.Error, "request failed")
		span.RecordError(err)
		return fmt.Errorf("创建用户请求失败: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(startTime)
	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.Float64("http.duration_ms", float64(duration.Nanoseconds())/1e6),
	)

	if resp.StatusCode == http.StatusOK {
		// 解析响应以获取创建的用户信息
		var createdUser User
		if err := json.NewDecoder(resp.Body).Decode(&createdUser); err == nil {
			c.createdUsers = append(c.createdUsers, createdUser)
			span.SetAttributes(attribute.Int64("user.id", createdUser.ID))
			log.Printf("用户创建成功 - ID: %d, 姓名: %s, 电话: %s, 耗时: %.3fms",
				createdUser.ID, createdUser.Name, createdUser.Phone, float64(duration.Nanoseconds())/1e6)
		}
	} else {
		span.SetStatus(codes.Error, "non-200 status code")
		return fmt.Errorf("创建用户失败，状态码: %d", resp.StatusCode)
	}

	return nil
}

func (c *Client) getUserByName(ctx context.Context, name string) error {
	ctx, span := c.tracer.Start(ctx, "client.getUserByName")
	defer span.End()

	span.SetAttributes(attribute.String("user.query.name", name))

	url := fmt.Sprintf("%s/user?name=%s", c.serverURL, name)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		span.SetStatus(codes.Error, "failed to create request")
		span.RecordError(err)
		return fmt.Errorf("创建查询用户请求失败: %w", err)
	}

	startTime := time.Now()
	resp, err := c.httpClient.Do(req)
	if err != nil {
		span.SetStatus(codes.Error, "request failed")
		span.RecordError(err)
		return fmt.Errorf("查询用户请求失败: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(startTime)
	span.SetAttributes(
		attribute.Int("http.status_code", resp.StatusCode),
		attribute.Float64("http.duration_ms", float64(duration.Nanoseconds())/1e6),
	)

	if resp.StatusCode == http.StatusOK {
		log.Printf("查询用户成功 - 姓名: %s, 耗时: %.3fms", name, float64(duration.Nanoseconds())/1e6)
	} else if resp.StatusCode == http.StatusNotFound {
		span.SetAttributes(attribute.Bool("user.found", false))
		log.Printf("用户未找到 - 姓名: %s", name)
	} else {
		span.SetStatus(codes.Error, "non-200 status code")
		return fmt.Errorf("查询用户失败，状态码: %d", resp.StatusCode)
	}

	return nil
}

func (c *Client) randomBetween(min, max int) int {
	if max < min {
		max = min
	}
	return min + rand.Intn(max-min+1)
}

func (c *Client) generateRandomUser() User {
	nameIdx := c.randomBetween(0, len(c.names)-1)
	name := c.names[nameIdx]

	var gender string
	if c.randomBetween(1, 2) == 1 {
		gender = "male"
	} else {
		gender = "female"
	}

	phone := fmt.Sprintf("1%d", c.randomBetween(3000000000, 9999999999))
	email := fmt.Sprintf("%s@example.com", strings.ToLower(name))
	age := c.randomBetween(18, 80)

	return User{
		Name:   name,
		Gender: gender,
		Phone:  phone,
		Email:  email,
		Age:    age,
	}
}

func handleErr(err error, message string) {
	if err != nil {
		log.Fatalf("%s: %v", message, err)
	}
}
