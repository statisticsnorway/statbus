import React from 'react'
import { Button, Form } from 'semantic-ui-react'
import { wrapper } from 'helpers/locale'
import mapPropertyToComponent from 'helpers/componentMapper'
import styles from './styles.pcss'

const EditForm = ({ statUnit, errors, localize, onSubmit }) => {
  const inner = statUnit.properties.map(x => mapPropertyToComponent(x, errors))
  return (
    <div className={styles.edit}>
      <Form className={styles.form} onSubmit={onSubmit} error>
        {inner}
        <br />
        <Button className={styles.sybbtn} type="submit" primary>{localize('Submit')}</Button>
      </Form>
    </div>
  )
}

const { func } = React.PropTypes

EditForm.propTypes = {
  onSubmit: func.isRequired,
}

export default wrapper(EditForm)
