package com.chatrix.api.config;

import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@SecurityScheme(
        name = "bearerAuth",
        type = SecuritySchemeType.HTTP,
        scheme = "bearer",
        bearerFormat = "JWT"
)
public class OpenApiConfig {

    @Bean
    public OpenAPI chatrixOpenAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("Chatrix API")
                        .description("REST API for the Chatrix real-time chat platform")
                        .version("1.0.0")
                        .contact(new Contact()
                                .name("Chatrix Team")
                                .email("team@chatrix.com")));
    }
}
