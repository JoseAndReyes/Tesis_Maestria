# Cargar librerías necesarias
library(survey)

#' Estimador de Integración de Datos RegDI
#'
#' Esta función implementa el estimador de integración de datos RegDI que combina una muestra probabilística A con una muestra no probabilística B. Permite la calibración utilizando variables auxiliares comunes a ambas muestras para mejorar la eficiencia del estimador.
#'
#' @param data \code{data.frame}. Conjunto de datos que contiene las variables de interés y las variables de muestra.
#' @param y_A_col \code{string}. Nombre de la columna para la variable de interés en la muestra probabilística A.
#' @param y_B_col \code{string}. Nombre de la columna para la variable de interés en la muestra no probabilística B.
#' @param size_a \code{numeric}. Tamaño de la muestra probabilística A.
#' @param size_muestra_B \code{numeric}. Tamaño de la muestra no probabilística B.
#' @param N \code{numeric, optional}. Tamaño poblacional. Si es \code{NULL}, se estima a partir de los datos.
#' @param apply_correction \code{numeric}. Indicador para aplicar corrección:
#'   \itemize{
#'     \item \code{0}: Sin corrección.
#'     \item \code{1}: Errores en la muestra B.
#'     \item \code{2}: Errores en la muestra A.
#'   }
#' @param aux_vars \code{character vector, optional}. Vector con los nombres de variables auxiliares comunes a las muestras A y B que se incluirán como restricciones de calibración.
#' @param weights_A_col \code{string, optional}. Nombre de la columna en \code{data} que contiene los pesos de muestreo conocidos para la muestra probabilística A. Si es \code{NULL}, se utilizarán pesos inversos al tamaño de la muestra A (\code{1 / size_a}).
#'
#' @return \code{list}. Una lista con los siguientes componentes:
#'   \item{mean_RegDI}{Estima la media de la variable de interés utilizando el estimador RegDI.}
#'   \item{var_RegDI}{Estimación de la varianza del estimador RegDI.}
#'
#' @details
#' La función `RegDI` combina una muestra probabilística A con una muestra no probabilística B para estimar la media de una variable de interés. La calibración se realiza para ajustar los pesos de la muestra A de manera que coincidan con los totales conocidos de las variables auxiliares en la población. Si se proporcionan variables auxiliares, estas se incluyen en las restricciones de calibración, lo que puede mejorar la eficiencia del estimador.
#'
#' En el caso de errores de medición en las muestras, la función permite corregir la variable de interés basada en un modelo lineal ajustado con unidades de validación (unidades que pertenecen a ambas muestras A y B).
#'
#' @examples
#' \dontrun{
#' # Supongamos que tienes un data.frame 'datos_simul' con las columnas 'xi', 'yi', 'yi_ast'
#' # y que ya has definido las muestras A y B.
#'
#' # Crear variables auxiliares z1 y z2
#' datos_simul$z1 <- datos_simul$xi
#' datos_simul$z2 <- datos_simul$xi^2
#'
#' # Calcular la media verdadera de la población
#' media_verdadera <- mean(datos_simul$yi)
#'
#' # Usar la función RegDI sin variables auxiliares
#' resultado_sin_aux <- RegDI(
#'   data = datos_simul, 
#'   y_A_col = "yi", 
#'   y_B_col = "yi_ast", 
#'   size_a = 1000, 
#'   size_muestra_B = 5000, 
#'   N = 10000, 
#'   apply_correction = 0, 
#'   aux_vars = NULL,
#'   weights_A_col = NULL
#' )
#'
#' # Usar la función RegDI con variables auxiliares z1 y z2
#' resultado_con_aux <- RegDI(
#'   data = datos_simul, 
#'   y_A_col = "yi", 
#'   y_B_col = "yi_ast", 
#'   size_a = 1000, 
#'   size_muestra_B = 5000, 
#'   N = 10000, 
#'   apply_correction = 0, 
#'   aux_vars = c("z1", "z2"),
#'   weights_A_col = NULL
#' )
#'
#' # Calcular la diferencia con la media verdadera
#' diferencia_sin_aux <- abs(resultado_sin_aux$mean_RegDI - media_verdadera)
#' diferencia_con_aux <- abs(resultado_con_aux$mean_RegDI - media_verdadera)
#'
#' # Mostrar los resultados
#' print(paste("Diferencia RegDI sin variables auxiliares:", diferencia_sin_aux))
#' print(paste("Diferencia RegDI con variables auxiliares z1 y z2:", diferencia_con_aux))
#'
#' # Calcular la media con una muestra aleatoria simple de la muestra probabilística A
#' # Extraer la muestra probabilística A
#' muestra_A <- subset(datos_simul, muestra_A == 1)
#'
#' # Calcular la media simple de yi en muestra_A
#' media_muestra_A <- mean(muestra_A$yi)
#' diferencia_muestra_A <- abs(media_muestra_A - media_verdadera)
#'
#' print(paste("Diferencia media muestra A (simple):", diferencia_muestra_A))
#' }
#'
#' @export
RegDI <- function(data, y_A_col, y_B_col, 
                 size_a, size_muestra_B, N = NULL, 
                 apply_correction = 0, aux_vars = NULL,
                 weights_A_col = NULL) {
  
  # Determinar N si no se proporciona
  if (is.null(N)) {
    N <- nrow(data)
  }
  
  # Verificar que las columnas especificadas existan en el data frame
  required_cols <- c(y_A_col, y_B_col)
  if (!all(required_cols %in% names(data))) {
    stop("Las columnas especificadas para y_A_col o y_B_col no se encuentran en el data frame.")
  }
  
  # Verificar que las variables auxiliares existan si se proporcionan
  if (!is.null(aux_vars)) {
    if (!all(aux_vars %in% names(data))) {
      stop("Algunas de las variables auxiliares especificadas no se encuentran en el data frame.")
    }
  }
  
  # Inicializar columnas de muestra si no existen
  if (!"muestra_A" %in% names(data)) {
    data$muestra_A <- 0
  }
  if (!"muestra_B" %in% names(data)) {
    data$muestra_B <- 0
  }
  
  # Definir los pesos de muestreo iniciales
  if (!is.null(weights_A_col)) {
    if (!weights_A_col %in% names(data)) {
      stop("La columna especificada en weights_A_col no se encuentra en el data frame.")
    }
    data$d_i <- ifelse(data$muestra_A == 1, data[[weights_A_col]], 0)
  } else {
    data$d_i <- ifelse(data$muestra_A == 1, 1 / size_a, 0)  # Peso inverso al tamaño de la muestra A
  }
  
  # Calcular los totales poblacionales necesarios
  Nb <- sum(data$muestra_B, na.rm = TRUE)
  
  # Crear variables auxiliares
  data$uno <- 1
  data$delta_i <- data$muestra_B  # Usar 'delta_i' consistentemente
  data$delta_yi <- data$muestra_B * data[[y_B_col]]
  
  # Si hay variables auxiliares, crear las variables delta_z_i
  if (!is.null(aux_vars)) {
    for (z in aux_vars) {
      data[[paste0("delta_", z)]] <- data$muestra_B * data[[z]]
    }
  }
  
  # Preparar los totales poblacionales para calibración
  # Incluir totales para 'uno', 'delta_i', 'delta_yi'
  totals <- c(
    uno = sum(data$uno, na.rm = TRUE),
    delta_i = Nb,
    delta_yi = sum(data$delta_yi, na.rm = TRUE)
  )
  
  # Si se proporcionan variables auxiliares, calcular sus totales poblacionales
  if (!is.null(aux_vars)) {
    # Calcular los totales de las variables auxiliares multiplicadas por delta_i
    aux_totals <- colSums(data[, paste0("delta_", aux_vars)], na.rm = TRUE)
    # Añadir los totales auxiliares al vector de totales
    totals <- c(totals, aux_totals)
  }
  
  # Crear la fórmula de calibración
  # Incluir las variables auxiliares si se proporcionan
  if (!is.null(aux_vars)) {
    # Construir los nombres de las variables auxiliares calibradas
    delta_aux_vars <- paste0("delta_", aux_vars)
    calibration_formula <- as.formula(
      paste("~0 + uno + delta_i + delta_yi +", paste(delta_aux_vars, collapse = " + "))
    )
  } else {
    calibration_formula <- ~0 + uno + delta_i + delta_yi  # Sin variables auxiliares
  }
  
  # Crear el diseño de encuesta con los pesos iniciales
  design <- svydesign(
    ids = ~1, 
    data = data[data$muestra_A == 1, ], 
    weights = ~d_i
  )
  
  # Realizar la calibración
  calibrated_design <- calibrate(
    design,
    formula = calibration_formula,
    population = totals
  )
  
  if (apply_correction == 1) {
    # Escenario 2: Errores en la muestra B
    # No se requiere corrección adicional, solo calibración
    # Calcular el estimador RegDI usando y_A_col
    T_RegDI <- as.numeric(
      svymean(as.formula(paste("~", y_A_col)), calibrated_design)[1]
    )  # Media estimada
    V_RegDI <- as.numeric(
      svyvar(as.formula(paste("~", y_A_col)), calibrated_design)[1]
    )  # Varianza de la media estimada
    
  } else if (apply_correction == 2) {
    # Escenario 3: Errores en la muestra A
    # Necesitamos corregir y_A_col basado en y_B_col (suponiendo que y_B_col es sin errores)
    
    # Identificar unidades de validación: en muestra A y B
    validation_indices <- which(data$muestra_A == 1 & data$muestra_B == 1)
    
    if (length(validation_indices) < 2) {
      stop("No hay suficientes datos de validación en la muestra A para ajustar el modelo de error de medición.")
    }
    
    # Ajustar el modelo de errores de medición usando datos de validación
    fit <- lm(as.formula(paste(y_A_col, "~", y_B_col)), 
              data = data[validation_indices, ])
    
    beta_0 <- coef(fit)[1]
    beta_1 <- coef(fit)[2]
    
    # Corregir y_A_col para estimar y_i en la muestra A
    data$y_corrected <- data[[y_B_col]]  # Inicialmente igual a y_B_col
    data$y_corrected[data$muestra_A == 1] <- (data[[y_A_col]][data$muestra_A == 1] - beta_0) / beta_1
    
    # Actualizar delta_yi_corrected con y_corrected
    data$delta_yi_corrected <- data$muestra_B * data$y_corrected
    
    # Preparar los totales poblacionales corregidos para calibración
    totals_corrected <- c(
      uno = sum(data$uno, na.rm = TRUE),
      delta_i = Nb,
      delta_yi = sum(data$delta_yi_corrected, na.rm = TRUE)
    )
    
    if (!is.null(aux_vars)) {
      # Las variables auxiliares no se corrigen, se mantienen sus totales
      aux_totals_corrected <- colSums(data[, paste0("delta_", aux_vars)], na.rm = TRUE)
      # Añadir los totales auxiliares al vector de totales corregidos
      totals_corrected <- c(totals_corrected, aux_totals_corrected)
    }
    
    # Crear la fórmula de calibración corregida
    if (!is.null(aux_vars)) {
      # Construir los nombres de las variables auxiliares calibradas
      delta_aux_vars <- paste0("delta_", aux_vars)
      calibration_formula_corrected <- as.formula(
        paste("~0 + uno + delta_i + delta_yi +", paste(delta_aux_vars, collapse = " + "))
      )
    } else {
      calibration_formula_corrected <- ~0 + uno + delta_i + delta_yi  # Sin variables auxiliares
    }
    
    # Crear el diseño de encuesta corregido
    design_corrected <- svydesign(
      ids = ~1,
      data = data[data$muestra_A == 1, ],
      weights = ~d_i
    )
    
    # Realizar la calibración con los valores corregidos
    calibrated_design_corrected <- calibrate(
      design_corrected,
      formula = calibration_formula_corrected,
      population = totals_corrected
    )
    
    # Calcular el estimador RegDI con corrección
    T_RegDI <- as.numeric(
      svymean(~y_corrected, calibrated_design_corrected)[1]
    )  # Media estimada corregida
    V_RegDI <- as.numeric(
      svyvar(~y_corrected, calibrated_design_corrected)[1]
    )  # Varianza de la media estimada corregida
    
  } else {
    # Escenario 1: Sin corrección
    # Calcular el estimador RegDI usando y_A_col
    T_RegDI <- as.numeric(
      svymean(as.formula(paste("~", y_A_col)), calibrated_design)[1]
    )  # Media estimada
    V_RegDI <- as.numeric(
      svyvar(as.formula(paste("~", y_A_col)), calibrated_design)[1]
    )  # Varianza de la media estimada
  }
  
  # Retornar la media estimada y su varianza
  return(list(mean_RegDI = T_RegDI, var_RegDI = V_RegDI))
}
